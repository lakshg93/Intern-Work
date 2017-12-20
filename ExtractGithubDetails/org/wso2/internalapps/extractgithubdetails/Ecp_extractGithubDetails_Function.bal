package org.wso2.internalapps.extractgithubdetails;

import org.wso2.ballerina.connectors.googlespreadsheet;
import ballerina.lang.errors;
import ballerina.utils.logger;
import ballerina.lang.jsons;
import ballerina.lang.messages;
import ballerina.data.sql;
import ballerina.net.http;
import ballerina.lang.strings;
import ballerina.lang.files;
import ballerina.lang.blobs;
import ballerina.lang.datatables;


function main (string[] args) {

    json configData = getConfigData(CONFIG_PATH);

    map propertiesMap = getSQLconfigData(configData);
    sql:ClientConnector dbConnector = create sql:ClientConnector(propertiesMap);

    googlespreadsheet:ClientConnector googleSpreadsheetConnector = {};

    string googleAccessToken;
    string googleRefreshToken;
    string googleClientID;
    string googleClientSecret;
    string gitCommitersSpreadsheetID;
    string gitCommiteersRange;
    string dateTimeRenderOptions;
    string valueRenderOptions;
    string fields;
    string majorDimensions;

    try{
        googleAccessToken = jsons:getString(configData, "$.googleAccessToken");
        googleRefreshToken = jsons:getString(configData, "$.googleRefreshToken");
        googleClientID = jsons:getString(configData,"$.googleClientId");
        googleClientSecret = jsons:getString(configData,"$.googleClientSecret");
        dateTimeRenderOptions = jsons:getString(configData,"$.dateTimeRenderOption");
        valueRenderOptions = jsons:getString(configData,"$.valueRenderOption");
        fields = jsons:getString(configData,"$.fields");
        majorDimensions = jsons:getString(configData,"$.majorDimensions");


        gitCommitersSpreadsheetID = jsons:getString(configData, "$.gitCommitersSheetID");
        gitCommiteersRange = jsons:getString(configData,"$.gitCommitersRange");
    }catch (errors:Error err){
        logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "Properties not defined in config.json: " + err.msg );
        return;
    }



    try {
        googleSpreadsheetConnector = create googlespreadsheet:ClientConnector(googleAccessToken,
                                                                              googleRefreshToken, googleClientID, googleClientSecret);
    } catch (errors:Error err) {
        logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + err.msg);

    }


    message spreadSheetResponse = {};
    json spreadSheetResponseJson;

    try {
        spreadSheetResponse = googlespreadsheet:ClientConnector.getCellData(googleSpreadsheetConnector,
                                                gitCommitersSpreadsheetID, gitCommiteersRange, dateTimeRenderOptions, valueRenderOptions,
                                                fields, majorDimensions);

        logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "Payload received : " +
                     jsons:toString(messages:getJsonPayload(spreadSheetResponse)));
        spreadSheetResponseJson = messages:getJsonPayload(spreadSheetResponse);
    }catch (errors:Error err) {

        logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + err.msg);
    }


    sql:Parameter[] selectTimeStampParam = [];
    json timeStampJson = readFromDb(dbConnector, selectTimeStampParam, READ_TIME_STAMP_GIT_DETAILS_QUERY);

    string lastReadTimeStamp = jsons:getString(timeStampJson[0],"$.timestamp");

    logger:info(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "Last Read Timestamp : " + lastReadTimeStamp);

    boolean startExtracting = false;
    int count = 0;
    while (count < lengthof spreadSheetResponseJson.values) {
        boolean proceed = false;

        string email;


        string currentTimeStamp = jsons:toString(spreadSheetResponseJson.values[count][0]);

        if(lastReadTimeStamp == currentTimeStamp){
            logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "Time Stamp found");
            startExtracting = true;
            count = count + 1;
        }
        if(startExtracting) {
            try {
                email = jsons:toString(spreadSheetResponseJson.values[count][9]);
                if(strings:contains(email,"wso2.com")){
                    proceed = true;
                }else{
                    logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + email + " is not a wso2 email");
                }

            } catch (errors:Error err) {

                logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "WSO2 Email not found for entry: " + count);
            }

            if (proceed) {

                sql:Parameter emailParam = {sqlType:"varchar", value:email};
                sql:Parameter[] selectIDParam = [emailParam];
                json employeeDetails = readFromDb(dbConnector, selectIDParam, READ_ID_FROM_EMPLOYEE_DETAILS_QUERY);

                boolean newEntry = false;
                int ID;
                string name;
                string fullName = "";

                try {
                    fullName = jsons:toString(spreadSheetResponseJson.values[count][6]);

                } catch (errors:Error err) {

                    logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "Name not found at the spreadsheet : " + count);
                }

                try {
                    ID = jsons:getInt(employeeDetails[0], "$.ID");

                } catch (errors:Error err) {
                    logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "This user is not found in the employee data table : " + email);
                    if (fullName != "") {
                        newEntry = true;
                    }
                }

                if (newEntry) {

                    sql:Parameter wso2_email_param = {sqlType:"varchar", value:email};
                    sql:Parameter[] newEntryParams = [wso2_email_param, wso2_email_param];

                    boolean newEntryInserted = updateToDB(dbConnector,newEntryParams,
                                                          INSERT_NEW_ENTRY_TO_EMPLOYEE_DETAILS_QUERY);
                    if(newEntryInserted){
                        logger:info(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                    "New Entry added to employee_names table : " + email);
                    } else{
                        logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                     "Error when inserting data to employee_names table : " + email);
                    }

                } else {
                    boolean updateData = true;
                    string githubUsername;
                    try {
                        githubUsername = jsons:toString(spreadSheetResponseJson.values[count][1]);

                    } catch (errors:Error err) {
                        updateData = false;
                        logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                     "Github User name not found for Entry:" + count);
                    }
                    string githubEmail = "";

                    try {
                        githubEmail = jsons:toString(spreadSheetResponseJson.values[count][11]);

                    } catch (errors:Error err) {

                        logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                     "Github Email not found at the spreadsheet:" + count);
                    }

                    if(githubEmail == ""){
                        githubEmail = findGithubEmail(githubUsername,fullName);
                        logger:debug(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                     "Github Email found using API. Email:" + githubEmail);

                    }
                    if (updateData) {

                        sql:Parameter ID_param = {sqlType:"varchar", value:ID};
                        sql:Parameter githubUsername_param = {sqlType:"varchar", value:githubUsername};
                        sql:Parameter githubEmail_param = {sqlType:"varchar", value:githubEmail};

                        sql:Parameter[] githubDetailsParam = [ID_param, githubUsername_param,
                                                              githubEmail_param, githubUsername_param,
                                                              githubEmail_param];

                        boolean updateGithubDetails = updateToDB(dbConnector, githubDetailsParam,
                                                                 UPDATE_GITHUB_DETAILS_QUERY);
                        if(updateGithubDetails){
                            logger:info(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                        "github_details table updated for user : " + email);
                        } else{
                            logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                                         "Error when updating data to github_details table : " + email);
                        }
                    }
                    count = count + 1;
                }
            } else {
                count = count + 1;
            }
        } else{
            count = count + 1;
        }
    }
    int responseCount = lengthof spreadSheetResponseJson.values;
    string timestamp = jsons:toString(spreadSheetResponseJson.values[responseCount-1][0]);

    sql:Parameter timeStampParam = {sqlType:"varchar", value:timestamp};
    sql:Parameter[] timeStampParams = [timeStampParam];
    boolean updateTimestamp = updateToDB(dbConnector, timeStampParams,
                                         UPDATE_TIME_STAMP_GIT_DETAILS_QUERY);
    if(updateTimestamp){
        logger:info(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "last_read_timestamp table updated: "+
                    timestamp);
    } else{
        logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG +
                     "Error when updating data to last_read_timestamp table : " + timestamp);
    }
}

function findGithubEmail(string username,string fullName)(string){
    json configData = getConfigData(CONFIG_PATH);

    string githubAccessToken;

    try{
        githubAccessToken = jsons:getString(configData, "$.github_Access_token");

    } catch (errors:Error err){
        logger:error(UPDATE_GITHUB_DETAILS_FUNCTION_TAG + "Properties not defined in config.json: " + err.msg );
        return "error";
    }


    string path = "/users/" + username + "/events/public";
    message request = {};
    message response = {};
    string email = "";

    http:ClientConnector githubConnector = create http:ClientConnector(GITHUB_DOMAIN_URL);
    messages:setHeader(request, "Content-Type", "application/json");
    messages:setHeader(request, "Authorization", "bearer " + githubAccessToken);

    response = http:ClientConnector.get(githubConnector, path, request);

    json githubjson = messages:getJsonPayload(response);
    logger:info(githubjson);

    boolean verifiedUser = false;
    int commitCount = 0;
    int repoCount = 0;
    int catchCount = 0;

    while(!verifiedUser || catchCount <5) {
        int a =1;
        try {
            string jsonPath = "$.[" + repoCount + "].payload.commits[" + commitCount + "].author.name";
            string name = jsons:getString(githubjson,jsonPath);
            if(name == username || name == fullName) {

                email, _ = (string)githubjson[repoCount].payload.commits[commitCount].author.email;
                verifiedUser = true;
                break;
            } else{
                commitCount = commitCount + 1;
            }
            catchCount = 0;
        } catch (errors:Error err) {
            commitCount = 0;
            repoCount = repoCount + 1;
            catchCount = catchCount + 1;
            if(catchCount == 5){
                //iterate until 5 exceptions
                verifiedUser = true;
                break;
            }

        }
    }
    return email;
}

function getConfigData(string filePath)(json){

    files:File configFile = {path: filePath};

    try{
        files:open(configFile, "r");
        logger:info(filePath + " file found");

    } catch (errors:Error err) {
        logger:error(filePath + " file not found. " + err.msg);
    }

    var content, numberOfBytes = files:read(configFile, NO_OF_BYTES_READ);
    logger:debug(filePath + " content read");

    files:close(configFile);
    logger:debug(filePath + " file closed");

    string configString = blobs:toString(content, "utf-8");

    try{
        json configJson = jsons:parse(configString);
        return configJson;

    } catch (errors:Error err) {
        logger:error("JSON syntax error found in config.json. " + err.msg);

    }

    return null;


}

function getSQLconfigData(json configData)(map){

    string jdbcUrl;
    string mySQLusername;
    string mySQLpassword;


    try {
        jdbcUrl = jsons:getString(configData, "$.jdbcUrl");
        mySQLusername = jsons:getString(configData, "$.mySQLusername");
        mySQLpassword = jsons:getString(configData, "$.mySQLpassword");

    } catch (errors:Error err) {
        logger:error("Properties not defined in config.json: " + err.msg );
    }

    map propertiesMap = {"jdbcUrl": jdbcUrl,"username": mySQLusername,"password": mySQLpassword};

    return propertiesMap;

}


function updateToDB(sql:ClientConnector dbConnector, sql:Parameter[] Params, string query) (boolean) {
    boolean sucessfulTransaction = false;
    transaction {
        sql:ClientConnector.update(dbConnector, query, Params);
    }aborted {
    logger:error("transaction aborted");

}committed {
sucessfulTransaction = true;
}
return sucessfulTransaction;
}

function readFromDb (sql:ClientConnector dbConnector, sql:Parameter[] Params, string query) (json) {

    datatable dt = sql:ClientConnector.select(dbConnector, query, Params);
    var selectJson, _ = <json>dt;
    logger:debug("Query:" + query + "Result" + jsons:toString(selectJson));
    datatables:close(dt);
    return selectJson;

}





