package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.lang.jsons;
import ballerina.net.http;
import ballerina.data.sql;
import ballerina.utils.logger;


@http:configuration{basePath:"/internal/ECP/Patch", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}
service<http> PatchService {

    json configData = getConfigData(CONFIG_PATH);

    map pmtPropertiesMap = getSQLconfigData(jsons:getJson(configData, "$.Database.PMT"));
    sql:ClientConnector pmtDbConnector = create sql:ClientConnector(pmtPropertiesMap);


    @http:GET {}
    @http:Path {value:"/patchDetails/{workmail}"}
    resource patchDetails (message m, @http:PathParam {value:"workmail"} string workmail) {

        logger:info(PATCH_RESOURCE_TAG + " : patchDetails Resource invoked");
        string emailAddress = workmail + EMAIL_DOMAIN;

        sql:Parameter projectKey={sqlType:"varchar",value:emailAddress};
        sql:Parameter[] params = [projectKey];
        json patchDetails = readFromDb(pmtDbConnector, params, GET_PATCH_DETAILS_QUERY);

        logger:debug(PATCH_RESOURCE_TAG + "PatchDetails Resource responded Sucessfully." + jsons:toString(patchDetails));
        message response = {};
        messages:setJsonPayload(response, patchDetails);
        reply response;

    }
}








