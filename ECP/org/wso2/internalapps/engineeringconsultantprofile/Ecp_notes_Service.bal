package org.wso2.internalapps.engineeringconsultantprofile;

import ballerina.lang.messages;
import ballerina.lang.jsons;
import ballerina.net.http;
import ballerina.data.sql;
import ballerina.utils.logger;
import ballerina.lang.strings;
import ballerina.lang.errors;


@http:configuration{basePath:"/internal/ECP/Notes", httpsPort: 9098,
                    keyStoreFile: "${BALLERINA_HOME}/bre/security/wso2carbon.jks",
                    keyStorePass: "wso2carbon", certPass: "wso2carbon"}
service<http> NotesService {

    json configData = getConfigData(CONFIG_PATH);

    map notesPropertiesMap = getSQLconfigData(jsons:getJson(configData,"$.Database.Notes"));
    sql:ClientConnector notesDbConnector = create sql:ClientConnector(notesPropertiesMap);


    @http:POST {}
    @http:Path {value:"/fetch"}
    resource readNotes (message m) {

        logger:info("ReadNotes Resource invoked");

        json payload;
        message response={};
        string engineerEmail;
        string managerEmail;
        string jwt;
        try {

            payload = messages:getJsonPayload(m);
            logger:debug(READ_NOTES_RESOURCE_TAG + "Payload received : " + jsons:toString(payload));

            jwt = jsons:getString(payload,"$.JWT");
            engineerEmail = jsons:getString(payload,"$.profile");
            managerEmail = jsons:getString(payload,"$.user");
        } catch (errors:Error err) {
            logger:error(READ_NOTES_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"Error found in input data"};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }

        json authorizedJson = validateUser(jwt);
        boolean authorized = jsons:getBoolean(authorizedJson,"Authorized");

        if(authorized) {

            sql:Parameter managerEmailParam = {sqlType:"varchar", value:managerEmail};
            sql:Parameter engineerEmailParam = {sqlType:"varchar", value:engineerEmail};
            sql:Parameter[] personalNotesParams = [managerEmailParam, engineerEmailParam];


            json personalNotesJson = readFromDb(notesDbConnector, personalNotesParams, READ_PERSONAL_NOTES_QUERY);

            logger:debug(READ_NOTES_RESOURCE_TAG + "Personal Notes Received" + jsons:toString(personalNotesJson));

            sql:Parameter[] sharedNotesParams = [engineerEmailParam];
            json sharedNotesJson = readFromDb(notesDbConnector, sharedNotesParams, READ_SHARED_NOTES_QUERY);
            logger:debug(READ_NOTES_RESOURCE_TAG + "Shared Notes Received" + jsons:toString(sharedNotesJson));

            string personalNote;
            try {
                personalNote = jsons:toString(personalNotesJson[0].notes);
            } catch (errors:Error err) {
                logger:debug(READ_NOTES_RESOURCE_TAG + "No personal Notes for the manager");
            }

            json ownSharedNote = jsons:getJson(sharedNotesJson, "$.[?(@.manager_id=='" + managerEmail + "')].notes");
            json otherNotes = jsons:getJson(sharedNotesJson, "$.[?(@.manager_id!='" + managerEmail + "')]");

            string ownSharedNoteString;
            try {
                ownSharedNoteString = jsons:toString(ownSharedNote[0]);
            } catch (errors:Error err) {
                logger:debug(READ_NOTES_RESOURCE_TAG + "No personal Notes for the manager");
            }



            json jsonResponse = {
                                    "employee_id":engineerEmail,
                                    "manager_id":managerEmail,
                                    "personal_notes":jsons:toString(personalNote),
                                    "own_shared_note":ownSharedNoteString,
                                    "shared_notes":otherNotes

                                };

            logger:debug(READ_NOTES_RESOURCE_TAG + "ReadNotes Resource responded Successfully" + jsons:toString(jsonResponse));
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }else {

            logger:error(READ_NOTES_RESOURCE_TAG + "User is not authorized");
            json jsonResponse = {"error":true, "message":"User is not authorized"};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }

    }

    @http:POST {}
    @http:Path {value:"/update"}
    resource updateNotesTable(message m){

        logger:info(UPDATE_NOTES_RESOURCE_TAG + "updateNotesTable resource invoked");

        json payload;
        message response = {};
        string tableType;
        string profile;
        string user;
        string updateNote;
        string jwt;

        try {

            payload = messages:getJsonPayload(m);
            logger:debug(UPDATE_NOTES_RESOURCE_TAG + "Payload received : " + jsons:toString(payload));

            jwt = jsons:getString(payload,"$.JWT");
            tableType = jsons:getString(payload, "$.noteType");
            profile = jsons:getString(payload, "$.profile");
            user = jsons:getString(payload, "$.user");
            updateNote = jsons:getString(payload, "$.updatedNote");
            updateNote = checkForInjections(updateNote);


        } catch (errors:Error err) {
            logger:error(UPDATE_NOTES_RESOURCE_TAG + err.msg);

            json jsonResponse = {"error":true, "message":"No input data found"};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }

        json authorizedJson = validateUser(jwt);
        boolean authorized = jsons:getBoolean(authorizedJson,"Authorized");
        if(authorized) {

            sql:Parameter managerEmailParam = {sqlType:"varchar", value:user};
            sql:Parameter employeeEmailParam = {sqlType:"varchar", value:profile};
            sql:Parameter notesParam = {sqlType:"varchar", value:updateNote};
            sql:Parameter[] params = [managerEmailParam, employeeEmailParam, notesParam, notesParam];

            boolean updateNotesBoolean;

            if (tableType == "personal") {
                updateNotesBoolean = updateToDB(notesDbConnector, params, UPDATE_PERSONAL_NOTES_QUERY);
            } else if (tableType == "shared") {
                updateNotesBoolean = updateToDB(notesDbConnector, params, UPDATE_SHARED_NOTES_QUERY);
            } else {

                logger:error(UPDATE_NOTES_RESOURCE_TAG + "Wrong Table selected");
                json jsonResponse = {"error":true, "message":"Wrong Table selected"};
                messages:setJsonPayload(response, jsonResponse);
                reply response;
            }


            json jsonResponse = {"error":!updateNotesBoolean};
            messages:setJsonPayload(response, jsonResponse);
            if (updateNotesBoolean) {
                logger:debug(UPDATE_NOTES_RESOURCE_TAG + "Update Notes resource responsed successfully");
            } else {
                logger:error(UPDATE_NOTES_RESOURCE_TAG + "Update Notes resource failed");
            }


            reply response;
        }else{
            logger:error(UPDATE_NOTES_RESOURCE_TAG + "User is not authorized");
            json jsonResponse = {"error":true, "message":"User is not authorized"};
            messages:setJsonPayload(response, jsonResponse);
            reply response;
        }
    }

}

function checkForInjections (string script) (string) {

    if(strings:contains(script,"<script>")){
        script = strings:replace(script,"<script>"," ");
        script = strings:replace(script,"<\\script>"," ");
    }
    return script;
}
