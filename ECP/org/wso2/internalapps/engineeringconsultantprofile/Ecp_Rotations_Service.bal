package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.net.http;
import ballerina.data.sql;
import ballerina.utils.logger;
import ballerina.lang.jsons;
import ballerina.lang.errors;



@http:configuration{basePath:"/internal/ECP/RotationFeedback", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}
service<http> RotationFeedbackService {

    json configData = getConfigData(CONFIG_PATH);

    map rotationsDetailsPropertiesMap = getSQLconfigData(jsons:getJson(configData,"$.Database.Rotations"));
    sql:ClientConnector rotationsDbConnector = create sql:ClientConnector(rotationsDetailsPropertiesMap);


    @http:POST {}
    @http:Path {value:"/details/{workmail}"}
    resource rotationFeedback (message m, @http:PathParam {value:"workmail"} string workmail) {

        string emailAddress = workmail + EMAIL_DOMAIN;

        logger:info(ROTATION_FEEDBACK_RESOURCE_TAG + "rotationFeedback Resource invoked");

        json payload;
        string jwt;
        try {
            payload = messages:getJsonPayload(m);
            jwt = jsons:getString(payload, "$.JWT");
            logger:debug(ROTATION_FEEDBACK_RESOURCE_TAG + jsons:toString(payload));

        } catch (errors:Error err) {
            logger:error(ROTATION_FEEDBACK_RESOURCE_TAG + "JWT is not found in the message" + err.msg);

            json jsonResponse = {"error":true, "message":"JWT not found"};
            message response = {};
            messages:setJsonPayload(response, jsonResponse);
            reply response;

        }

        json authorizedJson = validateUser(jwt);
        boolean authorized = jsons:getBoolean(authorizedJson, "Authorized");

        if (authorized) {

            sql:Parameter projectKey = {sqlType:"varchar", value:emailAddress};
            sql:Parameter[] params = [projectKey];

            json rotationFeedbackDetails = readFromDb(rotationsDbConnector, params, GET_ROTATION_FEEDBACK_QUERY);

            logger:debug("rotationFeedback Reseource response :" + jsons:toString(rotationFeedbackDetails));
            json responseJson = {
                              "feedback" : [],
                              "error" : false
                            };
            //rotationFeedbackDetails["error"] = false;
            jsons:addToArray(responseJson,"$.feedback",rotationFeedbackDetails);
            message response = {};
            messages:setJsonPayload(response, responseJson);
            reply response;

        }else{
            logger:error(ROTATION_FEEDBACK_RESOURCE_TAG + "User is not authorized");
            json jsonResponse = {"error":true, "message":"User is not Authorized"};
            message response = {};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }
    }



}









