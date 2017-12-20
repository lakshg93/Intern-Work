package org.wso2.internalapps.engineeringconsultantprofile;


import org.wso2.ballerina.connectors.googlespreadsheet;
import ballerina.utils.logger;
import ballerina.lang.errors;
import ballerina.lang.jsons;
import ballerina.lang.messages;
import ballerina.data.sql;
import ballerina.lang.strings;


function main (string[] args) {


    json configData = getConfigData(CONFIG_PATH);
    map propertiesMap = getSQLconfigData(jsons:getJson(configData, "$.Database.QSP"));
    sql:ClientConnector dbConnector = create sql:ClientConnector(propertiesMap);


    string gmailAccessToken;
    string gmailRefreshToken;
    string gmailClientId;
    string gmailClientSecret;
    string oldQspSpreadsheetId;

    string valueInputOptions;
    string fields;
    string oldQspRange;
    string dateTimeRenderOption;
    string valueRenderOption;
    string majorDimensions;

    try {
        //Getting data from the config.json

        gmailAccessToken = jsons:getString(configData, "$.gmailAccessToken");
        gmailRefreshToken = jsons:getString(configData, "$.gmailRefreshToken");
        gmailClientId = jsons:getString(configData, "$.gmailClientId");
        gmailClientSecret = jsons:getString(configData, "$.gmailClientSecret");

        oldQspSpreadsheetId = jsons:getString(configData, "$.oldQspSpreadsheetId");

        valueInputOptions = jsons:getString(configData, "$.valueInputOptions");
        fields = jsons:getString(configData, "$.fields");
        oldQspRange = jsons:getString(configData, "$.oldQspRange");
        dateTimeRenderOption = jsons:getString(configData, "$.dateTimeRenderOption");
        valueRenderOption = jsons:getString(configData, "$.valueRenderOption");
        majorDimensions = jsons:getString(configData, "$.majorDimensions");

    } catch(errors:Error err) {
        logger:error("Properties not defined in config.json: " + err.msg );
        return;
    }






    googlespreadsheet:ClientConnector googleSpreadsheetConnector = {};

    try {
        logger:debug(OLD_QSP_TO_DB_SERVICE_TAG + "Creating Connector ");
        googleSpreadsheetConnector = create googlespreadsheet:ClientConnector(gmailAccessToken,
                                            gmailRefreshToken, gmailClientId, gmailClientSecret);
    } catch(errors: Error err){
        logger:error(OLD_QSP_TO_DB_SERVICE_TAG + "error when creating connector Error message:"+err.msg);
        return;
    }

    logger:debug(OLD_QSP_TO_DB_SERVICE_TAG + "Connector Created");
    message oldQspSheetResponse = {};
    json oldQspDetails;


    try {

        logger:debug(OLD_QSP_TO_DB_SERVICE_TAG + "Reading Old QSP Data");

        oldQspSheetResponse = googlespreadsheet:ClientConnector.getCellData(googleSpreadsheetConnector,
                              oldQspSpreadsheetId, oldQspRange, dateTimeRenderOption, valueRenderOption,
                              fields, majorDimensions); //read the filtered results from the sheet 2

        logger:debug(OLD_QSP_TO_DB_SERVICE_TAG + "Payload received : " +
                     jsons:toString(messages:getJsonPayload(oldQspSheetResponse)));
        oldQspDetails = messages:getJsonPayload(oldQspSheetResponse);


    }
    catch(errors: Error err){

        logger:error(OLD_QSP_TO_DB_SERVICE_TAG + "error when reading Data Error message:"+err.msg);
        return;
    }

    int totalQspEntryCount = lengthof oldQspDetails.values;
    int successfullyExtractedCount = 0;
    json summary = {
                       "Total_entries": totalQspEntryCount,
                       "Error_entry_count":0,
                       "Successfully_extracted_count":0,
                       "Error_entries":[]
                        };

    int count =0;
    while (count <lengthof oldQspDetails.values) {
        json rowJson;
        try{
            rowJson = restructureOldQsp(oldQspDetails.values[count]); // restructuring old QSP data to new QSP data structure

            if (jsons:toString(rowJson.teamMemberEmail) != "#N/A") {
                if (jsons:getBoolean(rowJson, "$.error") != true) {

                    transaction {
                        sql:Parameter teamMemberEmailParam = {sqlType:"varchar", value:rowJson.teamMemberEmail};
                        sql:Parameter rolePlayedParam = {sqlType:"varchar", value:rowJson.rolePlayed};
                        sql:Parameter qspNameParam = {sqlType:"varchar", value:rowJson.qspName};
                        sql:Parameter recommendedPositionParam = {sqlType:"varchar", value:rowJson.recommendedPosition};
                        sql:Parameter overallPerformanceParam = {sqlType:"varchar", value:rowJson.overallPerfomance};
                        sql:Parameter commentsParam = {sqlType:"varchar", value:rowJson.comments};
                        sql:Parameter feedbackByParam = {sqlType:"varchar", value:rowJson.feedbackBy};
                        sql:Parameter startDateParam = {sqlType:"varchar", value:rowJson.startDate};
                        sql:Parameter endDateParam = {sqlType:"varchar", value:rowJson.endDate};

                        sql:Parameter[] params = [teamMemberEmailParam, rolePlayedParam, qspNameParam,
                                                  recommendedPositionParam, overallPerformanceParam,
                                                  commentsParam, feedbackByParam, startDateParam,
                                                  endDateParam];


                        sql:ClientConnector.update(dbConnector, "INSERT INTO `old_qsp_details`" +
                                                                "VALUES (?,?,?,?,?,?,?,?,?)", params);

                    }aborted {
                        logger:error(OLD_QSP_TO_DB_SERVICE_TAG + "transaction aborted");

                    }committed {
                        successfullyExtractedCount = successfullyExtractedCount + 1;
                        logger:info(OLD_QSP_TO_DB_SERVICE_TAG + "transaction Committed");
                    }
                }else{
                    json error = {
                                     "Row_No":count + 2,
                                     "Error":  jsons:getBoolean(rowJson,"$.error_details")
                                 };
                    jsons:addToArray(summary, "$.Error_Entries", error);
                }

            }else{
                json error = {
                                 "Row_No":count + 2,
                                 "Error":  "No email address for " + jsons:toString(oldQspDetails.values[count][2])
                             };
                jsons:addToArray(summary, "$.Error_Entries", error);


            }
        }catch(errors:Error err){
            logger:error(OLD_QSP_TO_DB_SERVICE_TAG + err.msg);
            json error = {
                             "Row_No":count + 2,
                             "Error":  "Error in Transaction " + err.msg
                         };
            jsons:addToArray(summary,"$.Error_Entries",error);
        }

        count = count+1;

    }
    dbConnector.close();
    logger:debug(OLD_QSP_TO_DB_SERVICE_TAG + "Update Finished");
    summary["Error_Entry_count"] = lengthof summary.Error_Entries;
    summary["Successfully_ectracted_count"] = successfullyExtractedCount;
    logger:info(OLD_QSP_TO_DB_SERVICE_TAG + jsons:toString(summary));


}

function restructureOldQsp(json row)(json){
    //Restructuring Old QSP data to the new QSP data format

    json rowJson;

    try {

        string teamMemberEmail = jsons:toString(row[33]);
        string rolePlayed = jsons:toString(row[3]);
        string qspName = jsons:toString(row[4]);
        string feedbackBy = jsons:toString(row[0]);

        string date = jsons:toString(row[5]);

        json datesJson = getDates(date);

        string commentRecommendAsLead = jsons:toString(row[31]);
        string commentRecommendAsConsultant = jsons:toString(row[32]);

        int consultantCommentLength = strings:length(commentRecommendAsConsultant);
        int leadCommentLength = strings:length(commentRecommendAsLead);

        string comment1 = strings:subString(commentRecommendAsConsultant, 2, consultantCommentLength);
        string comment2 = strings:subString(commentRecommendAsLead, 2, leadCommentLength);

        string comments = "Recommend as a Consultant comment:" + comment1 + "\nRecommend as a Lead Comment:"
                          + comment2;

        int reviewCount = 7;
        int reviewTotal = 0;
        while (reviewCount < 31) {
            int performanceRating = reviewRating(jsons:toString(row[reviewCount]));
            reviewTotal = reviewTotal + performanceRating;
            reviewCount = reviewCount + 1;
        }

        int average = reviewTotal / 25;

        string recommendedPosition;
        string overallPerfomance;

        string[] reviews = ["Needs Improvement", "Successful", "Exceptional"];
        overallPerfomance = reviews[average];

        if (strings:contains(commentRecommendAsLead, "+1")) {
            recommendedPosition = "Lead";
        }
        else if (strings:contains(commentRecommendAsConsultant, "+1")) {
            recommendedPosition = "Consultant";
        }
        else {
            recommendedPosition = "Trainee";
        }

        rowJson = {
                           "teamMemberEmail" : teamMemberEmail,
                           "rolePlayed" : rolePlayed,
                           "qspName" : qspName,
                           "recommendedPosition" :recommendedPosition,
                           "overallPerfomance" :overallPerfomance,
                           "comments" :comments,
                           "feedbackBy" :feedbackBy,
                           "startDate" :datesJson.startDate,
                           "endDate" : datesJson.endDate,
                            "error":false
                       };

    }catch(errors:Error err){
        logger:error(OLD_QSP_TO_DB_SERVICE_TAG + err.msg);
        rowJson["error"] = true;
        rowJson["error_details"] = "Error in Restructuring " + err.msg;
    }
    return rowJson;
}

function reviewRating(string reviewName)(int){

    reviewName= strings:toUpperCase(reviewName);
    int rating = 0;
    if(strings:contains(reviewName, "MEETS")){
        rating =1;
    }else if(strings:contains(reviewName, "EXCEEDED")) {
        rating = 2;
    }
    return rating;

}

function getDates(string date)(json){

    int firstindex = strings:indexOf(date,"/");
    int lastindex = strings:lastIndexOf(date,"/");

    string start = strings:subString(date,firstindex - 2,firstindex + 8);
    string end = strings:subString(date,lastindex - 5,lastindex + 5);

    string startDate = formatDate(start);
    string endDate = formatDate(end);

    json dateJson={
                      "startDate" : startDate,
                      "endDate" : endDate
                  };
    return dateJson;
}


function formatDate(string date)(string){
    string[]dateArr = strings:split(date, "/");
    var val, _ = <int>dateArr[1];
    if(<int>val < 13){
        date = dateArr[2] + "-" + dateArr[1] + "-" + dateArr[0];
    }
    else{
        date = dateArr[2] + "-" + dateArr[0] + "-"+dateArr[1];
    }
    return date;


}

