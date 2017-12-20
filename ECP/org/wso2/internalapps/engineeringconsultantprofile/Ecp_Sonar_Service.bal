package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.lang.jsons;
import ballerina.net.http;
import ballerina.data.sql;
import ballerina.utils.logger;
import ballerina.lang.errors;
import ballerina.utils;
import ballerina.lang.strings;
import ballerina.lang.files;
import ballerina.lang.blobs;
import ballerina.lang.datatables;

@http:configuration{basePath:"/internal/ECP/Sonar", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}
service<http> SonarService {

    json configData = getConfigData(CONFIG_PATH);
    json constantData = getConfigData(CONSTANT_PATH);

    map pqdPropertiesMap = getSQLconfigData(jsons:getJson(configData, "$.Database.PQD"));
    sql:ClientConnector pqdDbConnector = create sql:ClientConnector(pqdPropertiesMap);

    map githubDetailsPropertiesMap = getSQLconfigData(jsons:getJson(configData, "$.Database.GithubDetails"));
    sql:ClientConnector githubDetailsDbConnector = create sql:ClientConnector(githubDetailsPropertiesMap);

    @http:GET {}
    @http:Path {value:"/issuesCount/{workMail}"}
    resource SonarIssueCountPerEngineer (message m, @http:PathParam {value:"workMail"} string workMail) {

        string gitHubMail;
        logger:info(SONAR_ISSUE_COUNT_RESOURCE_TAG + " SonarIssueCountPerEngineer Resource invoked");

        string profileEmail = workMail + EMAIL_DOMAIN;

        try {
            gitHubMail = getGithubEmail(profileEmail, githubDetailsDbConnector);
        } catch(errors: Error err){
            logger:error(SONAR_ISSUE_COUNT_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when getting github Email"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }

        logger:info(SONAR_ISSUE_COUNT_RESOURCE_TAG + " Github Email for the User: " + profileEmail
                    + ":" + gitHubMail);

        http:ClientConnector sonarcon = {};
        try {
            sonarcon = create http:ClientConnector(BASICURL_SONAR);
        } catch(errors: Error err){
            logger:error(SONAR_ISSUE_COUNT_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when creating sonar connector"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }


        message request = {};
        message requestH = {};
        message sonarResponse = {};
        json sonarJSONResponse = {};


        string Path = "/api/issues/search?resolved=no&ps=500&authors=" + gitHubMail;

        requestH = authHeader(request);

        try {
            sonarResponse = http:ClientConnector.get(sonarcon, Path, requestH);
            sonarJSONResponse = messages:getJsonPayload(sonarResponse);

        } catch(errors: Error err){
            logger:error(SONAR_ISSUE_COUNT_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when getting sonar details"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }

        logger:debug(SONAR_ISSUE_COUNT_RESOURCE_TAG + "Sonar Response:" +
                     jsons:toString(sonarJSONResponse));

        json sonarDetailsExtractedJson = {
                                              "issues":[]
                                          };

        string[] componentNamesArray = [];

        int issueNumber = 0;
        int componentCount =0;

        //Extracting the details from the Sonar response

        while (issueNumber < lengthof sonarJSONResponse.issues) {
            try {
                string typeOfIssue = toLowerCase(jsons:getString(sonarJSONResponse, "$.issues[" +
                                                                 issueNumber + "].type"));

                string severityOfIssue =  toLowerCase(jsons:getString(sonarJSONResponse, "$.issues["
                                                                  + issueNumber + "].severity"));
                string componentNameKey = jsons:getString(sonarJSONResponse, "$.issues[" + issueNumber
                                                                   + "].project");
                string componentName = getComponentName(componentNameKey, pqdDbConnector);

                boolean isIncluded = isAlreadyInculded(componentNamesArray, componentName);
                //to get the distinct repository names
                if (!isIncluded) {
                    componentNamesArray[componentCount] = componentName;
                    componentCount = componentCount + 1;
                }

                json detailsofOneIssue = {
                                             "componentOrRepo":componentName,
                                             "IssueType":typeOfIssue,
                                             "severityOfIssue":severityOfIssue
                                         };

                jsons:addToArray(sonarDetailsExtractedJson, "$.issues", detailsofOneIssue);

            }


            catch (errors:Error err) {
                logger:error(SONAR_ISSUE_COUNT_RESOURCE_TAG + err.msg);
            }
            issueNumber = issueNumber + 1;

        }

        logger:debug(SONAR_ISSUE_COUNT_RESOURCE_TAG + "Extracted Json:" + jsons:toString(sonarDetailsExtractedJson));


        json sonarIssuesNamesArray;
        json sonarSeverityNamesArray;
        json sonarPriorityNamesArray;
        try{
            sonarIssuesNamesArray = jsons:getJson(constantData,"$.sonarIssuesNamesArray");
            sonarSeverityNamesArray = jsons:getJson(constantData,"$.sonarSeverityNamesArray");
            sonarPriorityNamesArray = jsons:getJson(constantData,"$.sonarPriorityNamesArray");

        }catch(errors: Error err){
            logger:error(SONAR_ISSUE_COUNT_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when reading the config details"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }


        json finalJson = structureIssues(sonarDetailsExtractedJson,componentNamesArray,
                                    sonarIssuesNamesArray, sonarSeverityNamesArray, sonarPriorityNamesArray);

        finalJson["error"] = false;
        logger:debug(SONAR_ISSUE_COUNT_RESOURCE_TAG + "SonarIssueCountPerEngineer resource responsed successfully"
                     + jsons:toString(finalJson));
        message response = {};
        messages:setJsonPayload(response, finalJson);
        reply response;


    }

    @http:GET {}
    @http:Path {value:"/issuesDetails/{workMail}"}
    resource SonarIssueDetailsPerEngineer (message m, @http:PathParam {value:"workMail"} string workMail) {

        string gitHubMail;
        logger:info(SONAR_ISSUE_DETAILS_RESOURCE_TAG + " SonarIssueDetailsPerEngineer Resource invoked");

        try {
            gitHubMail = getGithubEmail(workMail + EMAIL_DOMAIN, githubDetailsDbConnector);
            logger:info(SONAR_ISSUE_DETAILS_RESOURCE_TAG + " : Github Email:" + gitHubMail);


        } catch(errors: Error err){
            logger:error(SONAR_ISSUE_DETAILS_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when getting github Email"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }


        http:ClientConnector sonarcon = {};

        try {
            sonarcon = create http:ClientConnector(BASICURL_SONAR);
        } catch(errors: Error err){
            logger:error(SONAR_ISSUE_DETAILS_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when creating sonar connector"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }


        message request = {};
        message requestH = {};
        message sonarResponse = {};
        json sonarJSONResponse = {};

        string Path = "/api/issues/search?resolved=no&ps=500&authors=" + gitHubMail;
        requestH = authHeader(request);

        try {
            sonarResponse = http:ClientConnector.get(sonarcon, Path, requestH);
            sonarJSONResponse = messages:getJsonPayload(sonarResponse);

        } catch(errors: Error err){
            logger:error(SONAR_ISSUE_DETAILS_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error when getting sonar details"};
            message response={};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }

        logger:debug(SONAR_ISSUE_DETAILS_RESOURCE_TAG + "Sonar Response:" + jsons:toString(sonarJSONResponse));

        int issueNumber = 0;
        while (issueNumber < lengthof sonarJSONResponse.issues) {
            try {
                string creationDate = jsons:getString(sonarJSONResponse, "$.issues[" + issueNumber + "].creationDate");
                string dateString = strings:subString(creationDate, 0, 10);

                string componentNameKey = jsons:getString(sonarJSONResponse, "$.issues[" + issueNumber + "].project");
                string componentName = getComponentName(componentNameKey, pqdDbConnector);
                jsons:set(sonarJSONResponse, "$.issues[" + issueNumber + "].component", componentName);
                jsons:set(sonarJSONResponse, "$.issues[" + issueNumber + "].creationDate", dateString);
            }catch(errors:Error err){
                logger:error(SONAR_ISSUE_DETAILS_RESOURCE_TAG + err.msg);
            }
            issueNumber = issueNumber + 1;
        }
        sonarJSONResponse["error"] = false;
        logger:debug(SONAR_ISSUE_DETAILS_RESOURCE_TAG + "SonarIssueDetailsPerEngineer resource responsed successfully. "
                     + jsons:toString(sonarJSONResponse));
        message response = {};
        messages:setJsonPayload(response, sonarJSONResponse);
        reply response;


    }

}

function toLowerCase(string upperCaseString)(string){
    string fistLetter = strings:subString(upperCaseString,0,1);
    string otherLetters = strings:subString(upperCaseString,1,strings:length(upperCaseString));
    string lowerCaseString = fistLetter + strings:toLowerCase(otherLetters);

    if(lowerCaseString == "Code_smell"){
        lowerCaseString = "Code Smell";
    }
    return lowerCaseString;
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
    logger:debug("Query:" + query + "Result:" + jsons:toString(selectJson));
    datatables:close(dt);
    return selectJson;

}


function structureIssues (json dataJson, string[] namesArray, json issueTypesJson, json severityTypesJson,
                                json priorityTypesJson) (json) {

    json finalJson = {
                         "MainChart":{
                                         "issues":[],
                                         "severity":[]
                                     },
                         "drillDowns" : [],
                         "breakDownByComponentOrRepo":[]

                     };


    json totalSeverityBreakDownJson = getBreakdown("severityOfIssue", severityTypesJson, dataJson, "issues.");
    finalJson["totalSeverityBreakDown"] = totalSeverityBreakDownJson.BreakDown;

    if(lengthof priorityTypesJson != 0) {
        //for sonar issues priorityTypesJson length is 0
        json totalPriorityBreakDownJson = getBreakdown("priorityOfIssue", priorityTypesJson, dataJson, "issues.");
        finalJson["totalPriorityBreakDown"] = totalPriorityBreakDownJson.BreakDown;
        finalJson.MainChart["priority"] = [];
    }


    int issueTypeIndex = 0;
    while(issueTypeIndex < lengthof issueTypesJson) {
        //Get the Issues under one specific  type
        json issuesJson = jsons:getJson(dataJson, "$.issues.[?(@.IssueType=='" +
                                        jsons:toString(issueTypesJson[issueTypeIndex]) + "')]");

        finalJson = breakDownbyIssueType(finalJson, "$.MainChart.issues",
                                    jsons:toString(issueTypesJson[issueTypeIndex]), issuesJson,
                                    namesArray, severityTypesJson, priorityTypesJson);
        //Issues filterd by type is then sent to addToOutputJson Function to structure them and get the priority and severity breakdowns and add to finalJson

        issueTypeIndex = issueTypeIndex + 1;
    }

    return finalJson;
}

function getBreakdown(string breakDownType, json breakDownTypesJson, json dataJson, string jsonPath) (json) {
    //This function outputs the breakdown of no of issues per type in priority and severity

    //breakDownType can be Severity or Priority
    //breakDownTypeArray contains names of all types of severities or priorities
    //dataJson is the json which we want to get issue counts from
    //json path depends on the dataJson. We get breakdowns as a total and repository vise.


    json breakDownJson ={"BreakDown": []};

    int breakdownTypeIndex = 0;
    while (breakdownTypeIndex < lengthof breakDownTypesJson) {

        string path = "$." + jsonPath + "[?(@." + breakDownType + "=='" +
                      jsons:toString(breakDownTypesJson[breakdownTypeIndex]) + "')]";
        json issuesByBreakDownJson = jsons:getJson(dataJson,path);
        //Filter the issues which as the given priority or severity Type. Eg: issues with priority type 'Priority/High'
        int issueCount = jsons:getInt(issuesByBreakDownJson,"$.length()");
        json breakDown = {
                            "name":jsons:toString(breakDownTypesJson[breakdownTypeIndex]),
                            "y":issueCount
                        };

        jsons:addToArray(breakDownJson,"$.BreakDown",breakDown);
        breakdownTypeIndex = breakdownTypeIndex + 1;
    }

    return breakDownJson;

}

function breakDownbyIssueType (json outputJson, string jsonPath, string issueTypeName, json filteredJsonWithOneIssueType,
                         string[] namesArray, json severityTypesArray, json priorityTypesArray) (json) {
    //Structure the Results and update the outputJson
    //Issues under a type is structured and add to outputJson.
    //jsonPath is the path where we need to put data in outputJson
    //filteredJsonWithOneIssueType is the filtered json with a one issue type
    //These issues of one type is then breakdown by repository. repoNames contains the names of repositories that the user has
    //severityTypes array contains names of all the severity types.

    int totalIssueCountOfType = jsons:getInt(filteredJsonWithOneIssueType, "$.length()");

    json tempJson = {
                       "name":issueTypeName,
                       "y":totalIssueCountOfType,

                       "drilldown":issueTypeName
                   };

    if(totalIssueCountOfType > 0) {

        jsons:addToArray(outputJson,jsonPath,tempJson);
        outputJson = breakdownByComponentOrRepo(namesArray, filteredJsonWithOneIssueType, outputJson,
                                           issueTypeName, severityTypesArray, priorityTypesArray);

        json severityBreakDown = getBreakdown("severityOfIssue", severityTypesArray,
                                              filteredJsonWithOneIssueType, "");

        json severityJson = {
                                "issueType":issueTypeName,
                                "severityBreakDown": severityBreakDown.BreakDown
                                };
        jsons:addToArray(outputJson,"$.MainChart.severity",severityJson);

        if(lengthof priorityTypesArray !=0) {
            json priorityBreakDown = getBreakdown("priorityOfIssue", priorityTypesArray,
                                                  filteredJsonWithOneIssueType, "");
            json priorityJson = {
                                    "issueType":issueTypeName,
                                    "priorityBreakDown":priorityBreakDown.BreakDown
                                };

            jsons:addToArray(outputJson, "$.MainChart.priority", priorityJson);
        }
    }
    return outputJson;
}

function breakdownByComponentOrRepo (string[] namesArray, json dataJson, json finalJson, string issueName,
                            json severityTypes, json priorityTypes) (json) {
    int count =0;
    json keyValuePairs = {
                             "drillDowns":[]
                         };

    json breakDownJson = {
                             "componentOrRepoByIssueType" : []
                         };

    while (count < namesArray.length) {
        json issuesByRepo = jsons:getJson(dataJson, "$.[?(@.componentOrRepo=='" + namesArray[count] + "')]");
        int repoCount = jsons:getInt(issuesByRepo, "$.length()");

        if (repoCount > 0) {

            json key = [namesArray[count], repoCount];
            jsons:addToArray(keyValuePairs, "$.drillDowns", key);


            json severityBreakDown = getBreakdown("severityOfIssue",severityTypes,issuesByRepo,"");
            json severityJson = {
                                    "componentOrRepoName":namesArray[count],
                                    "severityBreakDown": severityBreakDown.BreakDown
                                };

            if(lengthof priorityTypes !=0) {
                json priorityBreakDown = getBreakdown("priorityOfIssue", priorityTypes, issuesByRepo, "");
                severityJson["priorityBreakDown"] = priorityBreakDown.BreakDown;
            }
            jsons:addToArray(breakDownJson, "$.componentOrRepoByIssueType", severityJson);

        }
        count = count + 1;

    }
    json repoDetails = {
                        "name":issueName,
                        "id":issueName,

                        "data":keyValuePairs.drillDowns
                    };

    jsons:addToArray(finalJson,"$.drillDowns",repoDetails);
    jsons:addToArray(finalJson,"$.breakDownByComponentOrRepo",breakDownJson);
    return finalJson;

}

function isAlreadyInculded (string[] namesArray, string name) (boolean) {
    int count =0;
    while(count< namesArray.length) {
        if(namesArray[count] == name) {
            return true;
        }
        count = count + 1;
    }
    return false;


}

function getComponentName(string sonar_project_key,sql:ClientConnector dbConnector) (string) {


    sql:Parameter projectKey={sqlType:"varchar",value:sonar_project_key};
    sql:Parameter[] params = [projectKey];

    json componentName = readFromDb(dbConnector,params,GET_COMPONENT_NAME_QUERY);

    string[] component = strings:split(sonar_project_key,":");
    string compname = strings:replace(component[1],".","-");

    try {
        compname = jsons:getString(componentName[0], "$.pqd_component_name");
    }catch (errors:Error err){
       // logger:debug(err.msg);
    }
    return compname;
}

function getGithubEmail(string email,sql:ClientConnector dbConnector) (string) {

    sql:Parameter projectKey={sqlType:"varchar",value:email};
    sql:Parameter[] params = [projectKey];

    json githubEmail = readFromDb(dbConnector,params,GET_GITHUB_EMAIL_QUERY);

    string githubMailString;
    try {
        githubMailString = jsons:getString(githubEmail[0], "$.github_email");
    }catch (errors:Error err){
        githubMailString ="";
    }
    if(githubMailString == ""){
        githubMailString = email;
    }
    return githubMailString;
}

function authHeader (message request) (message) {
    json configData = getConfigData(CONFIG_PATH);

    string token = jsons:getString(configData,"$.sonarAccessToken") + ":";
    string encodedToken = utils:base64encode(token);
    string passingToken = "Basic " + encodedToken;
    messages:setHeader(request, "Authorization", passingToken);
    messages:setHeader(request, "Content-Type", "application/json");
    return request;

}

function getConfigData(string filePath)(json){

    files:File configFile = {path: filePath};

    try{
        files:open(configFile, "r");
        logger:debug(filePath + " file found");

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








