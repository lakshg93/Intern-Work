package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.lang.jsons;
import ballerina.net.http;
import ballerina.data.sql;
import ballerina.utils.logger;
import ballerina.lang.time;


@http:configuration{basePath:"/internal/ECP/ReviewDetails", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}
service<http> ReviewDetailsService {

    json configData = getConfigData(CONFIG_PATH);

    map reviewsPropertiesMap = getSQLconfigData(jsons:getJson(configData,"$.Database.Reviews"));
    sql:ClientConnector reviewsDbConnector = create sql:ClientConnector(reviewsPropertiesMap);


    @http:GET {}
    @http:Path {value:"/summary/{workmail}"}
    resource ReviewSummary (message m, @http:PathParam {value:"workmail"} string workmail) {

        logger:info(REVIEW_SUMMARY_RESOURCE_TAG + "ReviewSummary resource Invoked");

        time:Time currentTime = time:currentTime();

        int year    = time:year(currentTime);
        int month   = time:month(currentTime);

        int currentQuarter = ((month - 1) / 3) + 1;

        int monthEndDate =31;
        if(currentQuarter == 2 || currentQuarter == 3) {
            monthEndDate =30;
        }

        string thisQEndDateString = year+"-"+ currentQuarter * 3 + "-" + monthEndDate;
        time:Time thisQEndDate = getTimeVariable(thisQEndDateString);


        sql:Parameter[] reviewTypesParams = [];
        json reviewTypesJson = readFromDb(reviewsDbConnector, reviewTypesParams, GET_REVIEW_TYPES_QUERY);

        logger:debug(REVIEW_SUMMARY_RESOURCE_TAG + "Review Types:" + jsons:toString(reviewTypesJson));

        int qCount = 0;
        json quarterDetails = {"Quarters":[]};
        int quarterNumber = currentQuarter;

        string timeFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ";

        while (qCount<5){
            time:Time quarterEndDate = time:subtractDuration(thisQEndDate, 0, qCount * 3, 0, 0, 0, 0, 0);
            string quarterEndDateString = time:format(quarterEndDate,timeFormat);

            if(quarterNumber == 0) {
                year = year - 1;
                quarterNumber = 4;
            }

            json quarter = {
                               "Quarter":year + " Q" + quarterNumber,
                               "Time":quarterEndDateString
                           };

            int reviewTypeCount = 0;
            while(reviewTypeCount< lengthof reviewTypesJson){
                string reviewType = jsons:getString(reviewTypesJson[reviewTypeCount],"$.reviewType");
                quarter[reviewType] = 0;
                reviewTypeCount = reviewTypeCount + 1;
            }

            jsons:addToArray(quarterDetails,"$.Quarters",quarter);

            qCount = qCount+1;
            quarterNumber = quarterNumber - 1;
        }

        quarterDetails.Quarters[4].Quarter = "Older";

        sql:Parameter projectKey={sqlType:"varchar",value:workmail + EMAIL_DOMAIN};
        sql:Parameter[] emailParams = [projectKey];

        json reviewDetailsJson = readFromDb(reviewsDbConnector, emailParams, GET_REVIEW_DATE_TYPE_QUERY);
        logger:debug(REVIEW_SUMMARY_RESOURCE_TAG + "Review Details :" + jsons:toString(reviewDetailsJson));

        int count = 0;
        while (count<lengthof reviewDetailsJson){
            time:Time codeReviewDate = getTimeVariable(jsons:getString(reviewDetailsJson[count],"$.review_date"));

            int qNumber = 4;
            while(qNumber >= 0) {
                time:Time quaterEndDate = time:parse(jsons:getString(quarterDetails,"$.Quarters["+ qNumber + "].Time"), timeFormat);
                if(codeReviewDate.time < quaterEndDate.time){

                    string reviewType = jsons:getString(reviewDetailsJson[count],"$.review_type");
                    int reviewCount = jsons:getInt(quarterDetails,"$.Quarters["+ qNumber + "].['" + reviewType + "']");
                    jsons:set(quarterDetails,"$.Quarters["+ qNumber + "].['" + reviewType + "']", reviewCount + 1);
                    break;

                }else{
                    qNumber = qNumber - 1;
                }

            }



            count = count +1;

        }


        logger:debug(REVIEW_SUMMARY_RESOURCE_TAG + " ReviewSummary Resource responded successfully."
                     + jsons:toString(quarterDetails));

        message response = {};
        messages:setJsonPayload(response, quarterDetails);
        reply response;

    }

    @http:GET {}
    @http:Path {value:"/details/{workmail}"}
    resource ReviewDetailsList (message m, @http:PathParam {value:"workmail"} string workmail) {

        logger:info(REVIEW_DETAILS_RESOURCE_TAG + "ReviewDetailsList Resource invoked.");

        string emailAddress = workmail + EMAIL_DOMAIN;

        sql:Parameter projectKey={sqlType:"varchar",value:emailAddress};
        sql:Parameter[] emailParams = [projectKey];

        json reviewDetailsJson = readFromDb(reviewsDbConnector, emailParams, READ_REVIEW_DETAILS_QUERY);


        logger:debug(REVIEW_DETAILS_RESOURCE_TAG + "ReviewDetailsList Resource responded Sucessfully."
                     + jsons:toString(reviewDetailsJson));

        message response = {};
        messages:setJsonPayload(response, reviewDetailsJson);
        reply response;

    }

    @http:GET {}
    @http:Path {value:"/singleReview/{workmail}/{reviewID}"}
    resource SingleReviewDetails (message m, @http:PathParam {value:"workmail"} string workmail ,
                                  @http:PathParam{value:"reviewID"} int reviewID) {

        logger:info(SINGLE_REVIEW_DETAIL_RESOURCE_TAG + "SingleReviewDetails Resource invoked.");

        sql:Parameter emailKey={sqlType:"varchar",value:workmail + EMAIL_DOMAIN};
        sql:Parameter reviewIDKey={sqlType:"integer",value:reviewID};
        sql:Parameter[] reviewParams = [emailKey,reviewIDKey];

        json reviewDetailsJson = readFromDb(reviewsDbConnector, reviewParams, READ_SINGLE_REVIEW_DETAILS_QUERY);

        logger:debug(SINGLE_REVIEW_DETAIL_RESOURCE_TAG + "SingleReviewDetails Resource responded Sucessfully."
                     + jsons:toString(reviewDetailsJson));
        message response = {};
        messages:setJsonPayload(response, reviewDetailsJson);
        reply response;

    }




}

function getTimeVariable(string dateString) (time:Time) {
    string timeFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    dateString = dateString + "T00:00:00.000-0000";
    time:Time date = time:parse(dateString, timeFormat);
    return date;

}








