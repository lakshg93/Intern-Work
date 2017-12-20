package org.wso2.internalapps.extractgithubdetails;


const string READ_TIME_STAMP_GIT_DETAILS_QUERY = "SELECT timestamp FROM last_read_timestamp";

const string READ_ID_FROM_EMPLOYEE_DETAILS_QUERY = "SELECT ID FROM employee_names WHERE wso2_email = ?";

const string INSERT_NEW_ENTRY_TO_EMPLOYEE_DETAILS_QUERY = "INSERT INTO employee_names (wso2_email)" +
                                                          "SELECT * FROM (SELECT ?) AS tmp " +
                                                          "WHERE NOT EXISTS (" +
                                                          "SELECT wso2_email FROM WSO2_employee_details.employee_names WHERE wso2_email = ? " +
                                                          ") LIMIT 1;";

const string UPDATE_GITHUB_DETAILS_QUERY = "INSERT INTO github_details (ID,github_username,github_email)
                        VALUES (?,?,?) ON DUPLICATE KEY UPDATE github_username = ? , github_email =? ";

const string UPDATE_TIME_STAMP_GIT_DETAILS_QUERY = "UPDATE last_read_timestamp SET timestamp=?";