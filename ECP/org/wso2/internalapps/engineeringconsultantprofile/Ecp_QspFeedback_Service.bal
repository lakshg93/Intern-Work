package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.lang.jsons;
import ballerina.lang.errors;
import ballerina.net.http;
import ballerina.utils.logger;
import org.wso2.ballerina.connectors.googlespreadsheet;
import ballerina.data.sql;
import ballerina.lang.datatables;
import ballerina.lang.strings;
import ballerina.utils;



struct oldQspStruct{
    string team_member_email;
    string role_played;
    string qsp_name;
    string recommended_position;
    string overall_performance;
    string comments;
    string feedback_by;
    string start_date;
    string end_date;
}


@http:configuration{basePath:"/internal/ECP/QSPFeedbacks", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}

service<http> QSPFeedbackService {

    json configData = getConfigData(CONFIG_PATH);

    map qspPropertiesMap = getSQLconfigData(jsons:getJson(configData, "$.Database.QSP"));
    sql:ClientConnector qspDbConnector = create sql:ClientConnector(qspPropertiesMap);

    @http:POST {}
    @http:Path {value:"/details/{workmail}"}
    resource ReadQspDetails (message m, @http:PathParam{value:"workmail"}string workmail) {
        //This resource is to get QSP data. New qsp data from the google sheet and old qsp data from db

        logger:info(QSP_DETAILS_SERVICE_TAG + "ReadQspDetails resource invoked");

        json payload;
        string jwt;
        try {
            payload = messages:getJsonPayload(m);
            jwt = jsons:getString(payload, "$.JWT");
            logger:debug(QSP_DETAILS_SERVICE_TAG + jsons:toString(payload));

        } catch (errors:Error err) {
            logger:error(QSP_DETAILS_SERVICE_TAG + "JWT is not found in the message" + err.msg);

            json jsonResponse = {"error":true, "message":"JWT not found"};
            message response = {};
            messages:setJsonPayload(response, jsonResponse);
            reply response;

        }


        json authorizedJson = validateUser(jwt);
        boolean authorized = jsons:getBoolean(authorizedJson,"Authorized");

        if (authorized) {


            string emailAddress = workmail + EMAIL_DOMAIN;

            logger:debug(QSP_DETAILS_SERVICE_TAG + "Email received : " + emailAddress);

            googlespreadsheet:ClientConnector googleSpreadsheetConnector = {};

            string googleAccessToken;
            string googleRefreshToken;
            string googleClientId;
            string googleClientSecret;
            string newQspSpreadsheetId;
            string filterPlaceHolderCell;
            string valueInputOptions;
            string fields;
            string newQspRange;
            string dateTimeRenderOption;
            string valueRenderOption;
            string majorDimensions;

            try {
                //extracting data from config.json

                googleAccessToken = jsons:getString(configData, "$.googleAccessToken");
                googleRefreshToken = jsons:getString(configData, "$.googleRefreshToken");
                googleClientId = jsons:getString(configData, "$.googleClientId");
                googleClientSecret = jsons:getString(configData, "$.googleClientSecret");
                newQspSpreadsheetId = jsons:getString(configData, "$.newQspSpreadsheetId");
                filterPlaceHolderCell = jsons:getString(configData, "$.filterPlaceHolderCell");
                valueInputOptions = jsons:getString(configData, "$.valueInputOptions");
                fields = jsons:getString(configData, "$.fields");
                newQspRange = jsons:getString(configData, "$.newQspRange");
                dateTimeRenderOption = jsons:getString(configData, "$.dateTimeRenderOption");
                valueRenderOption = jsons:getString(configData, "$.valueRenderOption");
                majorDimensions = jsons:getString(configData, "$.majorDimensions");

            } catch (errors:Error err) {
                logger:error("Properties not defined in config.json: " + err.msg);

                json jsonResponse = {"error":true, "message":"Properties not defined in config.json"};
                message response = {};
                messages:setJsonPayload(response, jsonResponse);
                reply response;

            }

            try {
                googleSpreadsheetConnector = create googlespreadsheet:ClientConnector(googleAccessToken,
                                                                                      googleRefreshToken, googleClientId, googleClientSecret);
            } catch (errors:Error err) {
                logger:info(QSP_DETAILS_SERVICE_TAG + err.msg);

                json jsonResponse = {"error":true, "message":"Error when creating connector"};
                message response = {};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }

            json editCellPayload = {
                                       "majorDimension":"ROWS",
                                       "values":[[emailAddress]]
                                   };

            message googlespreadsheetResponse = {};
            try {
                googlespreadsheetResponse = googlespreadsheet:ClientConnector.editCell(googleSpreadsheetConnector,
                                                                                       newQspSpreadsheetId, filterPlaceHolderCell, valueInputOptions,
                                                                                       editCellPayload, fields); //set the filtering email address on the sheet2

            } catch (errors:Error err) {
                logger:info(QSP_DETAILS_SERVICE_TAG + err.msg);

                json jsonResponse = {"error":true, "message":"Error when editing the filtering cell"};
                message response = {};
                messages:setJsonPayload(response, jsonResponse);
                reply response;

            }

            json googleSpreadsheetResponseJson;
            try {
                googlespreadsheetResponse = googlespreadsheet:ClientConnector.getMultipleCellData(googleSpreadsheetConnector,
                                                                                                  newQspSpreadsheetId, newQspRange, dateTimeRenderOption, valueRenderOption,
                                                                                                  fields, majorDimensions); //read the filtered results from the sheet 2

                googleSpreadsheetResponseJson = messages:getJsonPayload(googlespreadsheetResponse);
                logger:debug(QSP_DETAILS_SERVICE_TAG + "Payload received : " +
                             jsons:toString(googleSpreadsheetResponseJson));

            }
            catch (errors:Error err) {
                logger:info(QSP_DETAILS_SERVICE_TAG + err.msg);

                json jsonResponse = {"error":true, "message":"Error when reading new qsp spreadsheet"};
                message response = {};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }


            try {
                sql:Parameter projectKey = {sqlType:"varchar", value:emailAddress};
                sql:Parameter[] param = [projectKey];


                datatable oldQspTable = sql:ClientConnector.select(qspDbConnector, READ_OLD_QSP_DETAILS_QUERY, param);

                while (datatables:hasNext(oldQspTable)) {
                    any oldQspAny = datatables:next(oldQspTable);
                    var oldQspVariable, _ = (oldQspStruct)oldQspAny;

                    string oldQspStartDate = oldQspVariable.start_date;

                    string[] sDate = strings:split(oldQspStartDate, "-");
                    string sDateString = strings:subString(sDate[2], 0, 2);
                    oldQspStartDate = sDate[1] + "/" + sDateString + "/" + sDate[0];


                    string oldQspEndDate = oldQspVariable.end_date;
                    string[] eDate = strings:split(oldQspEndDate, "-");
                    string eDateString = strings:subString(eDate[2], 0, 2);
                    oldQspEndDate = eDate[1] + "/" + eDateString + "/" + eDate[0];

                    json rowJson = [
                                   oldQspVariable.team_member_email,
                                   oldQspVariable.role_played,
                                   oldQspVariable.qsp_name,
                                   oldQspVariable.recommended_position,
                                   oldQspVariable.overall_performance,
                                   oldQspVariable.comments,
                                   oldQspVariable.feedback_by,
                                   oldQspStartDate,
                                   oldQspEndDate

                                   ];
                    if (jsons:getString(googleSpreadsheetResponseJson, "$.valueRanges[0].values[0][0]") == "#N/A") {
                        googleSpreadsheetResponseJson.valueRanges[0].values = [];
                    }

                    jsons:addToArray(googleSpreadsheetResponseJson, "$.valueRanges[0].values", rowJson);

                }
                datatables:close(oldQspTable);
            }
            catch (errors:Error err) {
                logger:info(QSP_DETAILS_SERVICE_TAG + err.msg);

                json jsonResponse = {"error":true, "message":"Error when getting old qsp details"};
                message response = {};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }

            googleSpreadsheetResponseJson["error"] = false;
            logger:debug(QSP_DETAILS_SERVICE_TAG + "ReadQspDetails resource responded successfully. Response:"+ jsons:toString(googleSpreadsheetResponseJson));
            message response = {};
            messages:setJsonPayload(response, googleSpreadsheetResponseJson);
            reply response;

        }else{
            string errorMessage = jsons:toString(authorizedJson.Message);
            logger:error(QSP_DETAILS_SERVICE_TAG + errorMessage);

            json jsonResponse = {"error":true, "message":errorMessage};
            message response = {};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }
    }

}


function validateUser(string jwt)(json){

    string email;
    string decodedPayloadString;
    string roles;

    string[] webTokenArray;

    json decodedPayloadJson;

    boolean verified = false;

    string pubkey;
    json AuthorizedRoles;

    json configData = getConfigData(CONFIG_PATH);

    json response = {
                      "Authorized" : false,
                      "Message" : "User is not Authorized"
                    };

    try{
        pubkey = jsons:getString(configData,"$.pubkey");
        AuthorizedRoles = jsons:getJson(configData,"$.authorizedRoles");

    }catch(errors:Error err){
        logger:error(QSP_DETAILS_SERVICE_TAG + err.msg);
        response.Message = "Error when getting config data";
        return response;
    }

    try{

        webTokenArray= strings:split(jwt,"\\.");

        decodedPayloadString = utils:base64decode(webTokenArray[1]);
        decodedPayloadJson = jsons:parse(decodedPayloadString);

        verified = utils:getShaWithRsa(jwt,pubkey);
        logger:debug("Verified User :" + verified);

        email = jsons:toString(decodedPayloadJson["http://wso2.org/claims/emailaddress"]);

        if((strings:hasSuffix(email,"@wso2.com")) && verified ){

            roles = jsons:toString(decodedPayloadJson["http://wso2.org/claims/role"]);
            int authorizedRoleCount =0;
            while(authorizedRoleCount < lengthof AuthorizedRoles) {
                string authorizedRole = jsons:toString(AuthorizedRoles[authorizedRoleCount]);
                if(strings:contains(roles, authorizedRole)) {
                    response.Authorized = true;
                    response.Message = "User is Authorized";
                    break;
                }
                authorizedRoleCount = authorizedRoleCount+1;
            }

        } else {
            logger:debug("Not Authorized");
            response.Message = "JWT is not valid.";
        }

    } catch(errors:Error err) {
        logger:error("Authentication Failed" + err.msg);
        response.Message = "Authentication Failed " + err.msg;
    }

    return response;
}



