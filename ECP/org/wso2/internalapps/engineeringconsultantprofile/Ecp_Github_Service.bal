package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.lang.jsons;
import ballerina.net.http;
import ballerina.data.sql;
import ballerina.utils.logger;
import ballerina.lang.errors;
import ballerina.lang.strings;


@http:configuration{basePath:"/internal/ECP/Github", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}
service<http> GithubService {

    json configData = getConfigData(CONFIG_PATH);
    json constantData = getConfigData(CONSTANT_PATH);

    map githubDetailsPropertiesMap = getSQLconfigData(jsons:getJson(configData,"$.Database.GithubDetails"));
    sql:ClientConnector githubDetailsDbConnector = create sql:ClientConnector(githubDetailsPropertiesMap);

    @http:GET {}
    @http:Path {value:"/issuesCount/{workmail}"}
    resource GithubIssueCountPerEngineer (message m, @http:PathParam{value:"workmail"}string workmail) {

        logger:info(GITHUB_ISSUE_COUNT_RESOURCE_TAG + ": GithubIssueCountPerEngineer Resource invoked");

        json githubJsonResponse = getGithubResponse(workmail, githubDetailsDbConnector);
        logger:debug(GITHUB_ISSUE_COUNT_RESOURCE_TAG + "Github Response:" + jsons:toString(githubJsonResponse));


        if(jsons:getBoolean(githubJsonResponse, "$.error") == true) {
            logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + "Github Issues Resouce faild");

            message response={};
            messages:setJsonPayload(response, githubJsonResponse);
            reply response;

        }else{

            string repository;
            json githubDetailsExtractedJson = {
                                                  "issues":[]
                                              };
            string[] repoNamesArray = [];

            int issueNumber = 0;
            int repoCount =0;

            //Extracting the details from the github response
            try {
                while (issueNumber < lengthof githubJsonResponse.items) {
                    string typeOfIssue     = "Unknown";
                    string priorityOfIsuue = "Unknown";
                    string severityOfIssue = "Unknown";

                    string statusOfIssue = jsons:getString(githubJsonResponse, "$.items[" +
                                                           issueNumber + "].state"); //closed or open

                    if(statusOfIssue != "closed") {

                        string repositoryURL = jsons:getString(githubJsonResponse, "$.items[" +
                                                            issueNumber + "].repository_url");

                        string [] repoUrlBreakdownArray = strings:split(repositoryURL, "/");
                        int repoUrlLength = repoUrlBreakdownArray.length;
                        repository = repoUrlBreakdownArray[repoUrlLength - 2] + "-" +
                                     repoUrlBreakdownArray[repoUrlLength - 1];
                        //repository is in the type of "organization-repository name"

                        boolean isIncluded = isAlreadyInculded(repoNamesArray, repository);
                        //to get the distinct repository names
                        if(!isIncluded) {
                            repoNamesArray[repoCount] = repository;
                            repoCount = repoCount + 1;
                        }


                        int labelCount = 0;
                        try {
                            json labels = jsons:getJson(githubJsonResponse,"$.items[" + issueNumber
                                                                           + "].labels");

                            while (labelCount < lengthof labels) {
                                string labelName = jsons:getString(githubJsonResponse, "$.items[" +
                                                         issueNumber + "].labels[" + labelCount + "].name");
                                string labelNameUpperCase = strings:toUpperCase(labelName);
                                string[] labelBreakdown;
                                if (strings:contains(labelNameUpperCase, "TYPE")) {
                                    labelBreakdown = strings:split(labelName,"/");
                                    typeOfIssue = labelBreakdown[1];
                                }else if (strings:contains(labelNameUpperCase, "PRIORITY")) {
                                    labelBreakdown = strings:split(labelName,"/");
                                    priorityOfIsuue = labelBreakdown[1];

                                }else if (strings:contains(labelNameUpperCase, "SEVERITY")) {
                                    labelBreakdown = strings:split(labelName,"/");
                                    severityOfIssue = labelBreakdown[1];

                                }else if (strings:contains(labelNameUpperCase, "BUG")) {
                                    typeOfIssue = "Bug";
                                }else if (strings:contains(labelNameUpperCase, "ENHANCEMENT")) {
                                    typeOfIssue = "Improvement";
                                }else if (strings:contains(labelNameUpperCase, "TASK")) {
                                    typeOfIssue = "Task";
                                }
                                labelCount = labelCount + 1;

                            }
                        } catch (errors:Error err) {

                        }

                        json detailsofOneIssue = {
                                                     "componentOrRepo":repository,
                                                     "IssueType":typeOfIssue,
                                                     "priorityOfIssue":priorityOfIsuue,
                                                     "severityOfIssue":severityOfIssue
                                                 };

                        jsons:addToArray(githubDetailsExtractedJson, "$.issues", detailsofOneIssue);
                    }
                    issueNumber = issueNumber + 1;

                }
            }catch(errors:Error err){

                logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + err.msg);
                json jsonResponse = {"error":true, "message":"Error when getting github Response " + err.msg};
                message response={};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }

            json githubIssuesNamesArray;
            json githubSeverityNamesArray;
            json githubPriorityNamesArray;

            try{
                githubIssuesNamesArray = jsons:getJson(constantData,"$.githubIssuesNamesArray");
                githubSeverityNamesArray = jsons:getJson(constantData,"$.githubSeverityNamesArray");
                githubPriorityNamesArray = jsons:getJson(constantData,"$.githubPriorityNamesArray");

            }catch(errors: Error err){
                logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + err.msg);
                json jsonResponse = {"error":true, "message":"Error when reading the Constant details"};
                message response={};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }


            json finalJson = structureIssues(githubDetailsExtractedJson, repoNamesArray,
                           githubIssuesNamesArray, githubSeverityNamesArray, githubPriorityNamesArray);
            finalJson["error"] = false;
            logger:debug(GITHUB_ISSUE_COUNT_RESOURCE_TAG + "GithubIssueCountPerEngineer resource responsed successfully. "
                         + jsons:toString(finalJson));
            message outputResponse={};
            messages:setJsonPayload(outputResponse, finalJson);
            reply outputResponse;

        }
    }

    @http:GET {}
    @http:Path {value:"/issuesDetails/{workmail}"}
    resource GithubIssueDetailsPerEngineer (message m, @http:PathParam{value:"workmail"}string workmail) {

        logger:info(GITHUB_ISSUE_DETAILS_RESOURCE_TAG + ": GithubIssueDetailsPerEngineer Resource invoked");

        json githubJsonResponse = getGithubResponse(workmail, githubDetailsDbConnector);
        logger:debug(GITHUB_ISSUE_DETAILS_RESOURCE_TAG + "Github Response:" + jsons:toString(githubJsonResponse));


        if(jsons:getBoolean(githubJsonResponse, "$.error") == true) {
            logger:error(GITHUB_ISSUE_DETAILS_RESOURCE_TAG + "Github Issues Resouce faild");

            message response={};
            messages:setJsonPayload(response, githubJsonResponse);
            reply response;

        }else{

            string repository;
            json githubDetailsExtractedJson = {
                                                  "issues":[]
                                              };

            int issueNumber = 0;

            //Extracting the details from the github response
            try {
                while (issueNumber < lengthof githubJsonResponse.items) {

                    string statusOfIssue = jsons:getString(githubJsonResponse, "$.items[" +
                                                           issueNumber + "].state"); //closed or open

                    string typeOfIssue     = "Unknown";
                    string priorityOfIsuue = "Unknown";
                    string severityOfIssue = "Unknown";

                    if(statusOfIssue != "closed") {

                        string repositoryURL = jsons:getString(githubJsonResponse, "$.items[" +
                                                            issueNumber + "].repository_url");

                        string [] repoUrlBreakdownArray = strings:split(repositoryURL, "/");
                        int repoUrlLength = repoUrlBreakdownArray.length;
                        repository = repoUrlBreakdownArray[repoUrlLength - 2] + "-" +
                                     repoUrlBreakdownArray[repoUrlLength - 1];
                        //repository is in the type of "organization-repository name"
                        string title = jsons:getString(githubJsonResponse, "$.items[" +
                                                             issueNumber + "].title");
                        string createdDate = jsons:getString(githubJsonResponse, "$.items[" +
                                                             issueNumber + "].created_at");

                        createdDate = strings:subString(createdDate,0,10);

                        string htmlUrl = jsons:getString(githubJsonResponse, "$.items[" +
                                                                                   issueNumber + "].html_url");
                        int issueID = jsons:getInt(githubJsonResponse, "$.items[" +
                                                                             issueNumber + "].number");

                        int labelCount = 0;
                        json labels = jsons:getJson(githubJsonResponse,"$.items[" +
                                                             issueNumber + "].labels");


                        try {
                            while (labelCount < lengthof labels) { //checking first 3 labels of an issue
                                string labelName = jsons:getString(githubJsonResponse, "$.items[" +
                                                         issueNumber + "].labels[" + labelCount + "].name");
                                string labelNameUpperCase = strings:toUpperCase(labelName);
                                string[] labelBreakdown;
                                if (strings:contains(labelNameUpperCase, "TYPE")) {
                                    labelBreakdown = strings:split(labelName,"/");
                                    typeOfIssue = labelBreakdown[1];
                                } else if (strings:contains(labelNameUpperCase, "PRIORITY")) {
                                    labelBreakdown = strings:split(labelName,"/");
                                    priorityOfIsuue = labelBreakdown[1];

                                } else if (strings:contains(labelNameUpperCase, "SEVERITY")) {
                                    labelBreakdown = strings:split(labelName,"/");
                                    severityOfIssue = labelBreakdown[1];

                                }else if (strings:contains(labelNameUpperCase, "BUG")) {
                                    typeOfIssue = "Bug";

                                }else if (strings:contains(labelNameUpperCase, "TASK")) {
                                      typeOfIssue = "Task";
                                }else if (strings:contains(labelNameUpperCase, "ENHANCEMENT")) {
                                    typeOfIssue = "Improvement";
                                }
                                labelCount = labelCount + 1;

                            }
                        } catch (errors:Error err) {
                            //logger:info(GITHUB_ISSUE_DETAILS_RESOURCE_TAG + err.msg);
                        }

                        json detailsofOneIssue = {
                                                     "repository":repository,
                                                     "IssueType":typeOfIssue,
                                                     "priorityOfIssue":priorityOfIsuue,
                                                     "severityOfIssue":severityOfIssue,
                                                     "title": title,
                                                     "createdDate" : createdDate,
                                                     "htmlUrl" :htmlUrl,
                                                     "issueID" : issueID
                                                 };

                        jsons:addToArray(githubDetailsExtractedJson, "$.issues", detailsofOneIssue);
                    }
                    issueNumber = issueNumber + 1;

                }
            }catch(errors:Error err){

                logger:error(GITHUB_ISSUE_DETAILS_RESOURCE_TAG + err.msg);
                json jsonResponse = {"error":true, "message":"Error when getting github Response " + err.msg};
                message response={};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }

            githubDetailsExtractedJson["error"] = false;
            logger:debug(GITHUB_ISSUE_DETAILS_RESOURCE_TAG + "GithubIssueDetailsPerEngineer resource responsed successfully. "
                         + jsons:toString(githubDetailsExtractedJson));

            message outputResponse={};
            messages:setJsonPayload(outputResponse, githubDetailsExtractedJson);
            reply outputResponse;

        }
    }


}

function getGithubResponse(string email,sql:ClientConnector dbConnector)(json){
    //This function returns all the details about github issues under the email we provide.

    json configData = getConfigData(CONFIG_PATH);

    string githubAccessToken;

    try{
        githubAccessToken = jsons:getString(configData, "$.github_Access_token");
    }catch (errors:Error err){
        logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + "Properties not defined in config.json: " + err.msg );
        json jsonResponse = {"error":true, "message":"Error when getting Config Data " + err.msg};
        return jsonResponse;
    }


    string gitHubUserName;
    try {
        gitHubUserName = getGithubUserName(email + EMAIL_DOMAIN, dbConnector);
        logger:info("Github UserName Found: " + gitHubUserName);
    } catch(errors: Error err){
        logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG+err.msg);
        json jsonResponse = {"error":true, "message":"Error when getting github Email " + err.msg};
        return jsonResponse;
    }


    string path="/search/issues?q=assignee:" + gitHubUserName + "&per_page=100";

    message request = {};
    message response = {};

    http:ClientConnector githubCon = create http:ClientConnector(GITHUB_DOMAIN_URL);
    messages:setHeader(request, "Content-Type", "application/json");
    messages:setHeader(request, "Authorization", "bearer " + githubAccessToken);

    json githubjson;
    try {
        response = http:ClientConnector.get(githubCon, path, request);
        githubjson = messages:getJsonPayload(response);

        int totalIssuesCount = jsons:getInt(githubjson,"$.total_count");
        if(totalIssuesCount >100){
            response = collectDataFromPagination(response);
            githubjson=messages:getJsonPayload(response);

        }


    } catch(errors: Error err){
        logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + err.msg);
        json jsonResponse = {"error":true, "message":"Error when getting github Response " + err.msg};
        return jsonResponse;
    }
    githubjson["error"] = false;
    return githubjson;
}

function collectDataFromPagination(message response)(message ){
    //this function will handle pagination for httpGetForGithubMethod

    string linkHeader = "";
    json combinedJsonResponse = messages:getJsonPayload(response);

    boolean isLinkHeaderAvailable = true;
    message currentRequest = {};
    message currentResponse = response;
    while(isLinkHeaderAvailable){
        try {
            string rateLimitHeader = messages:getHeader(currentResponse, "x-ratelimit-remaining");
            linkHeader = messages:getHeader(currentResponse, "link");
            json links = splitLinkHeader(linkHeader);

            try {
                string nextLink = jsons:getString(links, "$.next");
                http:ClientConnector httpCon = create http:ClientConnector(nextLink);

                currentRequest = {};
                currentResponse = http:ClientConnector.get(httpCon, "", currentRequest);

                json currentJsonResponse = messages:getJsonPayload(currentResponse);

                int index = 0;
                while(index < lengthof currentJsonResponse.items){

                    jsons:addToArray(combinedJsonResponse, "$.items", jsons:getJson(currentJsonResponse,
                                                                            "$.items[" + index + "]"));
                    index = index + 1;
                }

            } catch (errors:Error err){
                isLinkHeaderAvailable = false;
            }
        } catch(errors:Error err){
            isLinkHeaderAvailable = false;
        }
    }

    message combinedResponse = {};
    messages:setJsonPayload(combinedResponse, combinedJsonResponse);
    return combinedResponse;
}

function splitLinkHeader(string linkHeader)(json){
    //this will parse the link header present in the github response

    if (strings:length(linkHeader) == 0) {
        logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + "Header length must be greater than zero");
    }
    string[] parts = strings:split(linkHeader, ",");
    json links = {};
    int i = 0;
    while (i < lengthof parts){
        string[] section = strings:split(parts[i], ";");
        if (lengthof section != 2){
            logger:error(GITHUB_ISSUE_COUNT_RESOURCE_TAG + "Header section could not be split on ';'");
        }
        string url = strings:trim(strings:replaceFirst(section[0], "<(.*)>", "$1"));
        string name = strings:subString(section[1], 6, strings:length(section[1]) -1 );
        jsons:addToObject(links, "$", name, url);
        i = i + 1;
    }
    return links;
}

function getGithubUserName(string email,sql:ClientConnector dbConnector) (string) {

    sql:Parameter projectKey={sqlType:"varchar",value:email};
    sql:Parameter[] params = [projectKey];

    json githubUserName = readFromDb(dbConnector, params, GET_GITHUB_USERNAME_QUERY);

    string githubUserNameString = email;
    try {
        githubUserNameString = jsons:getString(githubUserName[0], "$.github_username");
    }catch (errors:Error err){
        // logger:debug(err.msg);
    }
    return githubUserNameString;
}






