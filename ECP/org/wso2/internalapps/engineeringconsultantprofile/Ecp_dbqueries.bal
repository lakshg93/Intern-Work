package org.wso2.internalapps.engineeringconsultantprofile;


const string GET_GITHUB_EMAIL_QUERY = "SELECT github_email FROM employee_names "+
                                      "INNER JOIN github_details WHERE employee_names.ID = github_details.ID AND wso2_email = ?";
const string GET_GITHUB_USERNAME_QUERY = "SELECT github_username FROM employee_names "+
                                         "INNER JOIN github_details WHERE employee_names.ID = github_details.ID AND wso2_email = ?";

const string GET_PATCH_DETAILS_QUERY = "SELECT PATCH_NAME,BEST_CASE_ESTIMATE,MOST_LIKELY_ESTIMATE,
                                        WORST_CASE_ESTIMATE,DEVELOPMENT_STARTED_ON,PATCH_QUEUE_ID,SUPPORT_JIRA
                                        FROM PATCH_ETA INNER JOIN PATCH_QUEUE WHERE
                                        PATCH_ETA.PATCH_QUEUE_ID = PATCH_QUEUE.ID AND DEVELOPED_BY= ? AND STATUS = 0
                                        AND LC_STATE NOT IN ('Released','ReleasedNotInPublicSVN','ReleasedNotAutomated','OnHold','Broken')";

const string GET_COMPONENT_NAME_QUERY = "SELECT pqd_component_name FROM pqd_component WHERE sonar_project_key=?";

const string GET_ROTATION_FEEDBACK_QUERY = "SELECT er_rotation_type,er_rotation_start_date," +
                                           "er_rotation_end_date,er_feedback_rating,er_feedback,er_lead_email,er_feedback_reference "+
                                           "FROM er_feedback INNER JOIN er_rotation WHERE  "+
                                           "er_feedback.er_rotation_id = er_rotation.er_rotation_id AND er_rotation_type != "+
                                           "'QSP'  AND er_consultant_email = ? ORDER BY er_rotation_end_date DESC";

const string READ_PERSONAL_NOTES_QUERY = "SELECT notes FROM personal_notes WHERE manager_id =? AND employee_id =?";
const string READ_SHARED_NOTES_QUERY = "SELECT manager_id,notes FROM shared_notes WHERE employee_id = ?";

const string UPDATE_PERSONAL_NOTES_QUERY = "INSERT INTO personal_notes (manager_id,employee_id,notes)
                                            VALUES (?,?,?) ON DUPLICATE KEY UPDATE notes = ?";
const string UPDATE_SHARED_NOTES_QUERY = "INSERT INTO shared_notes (manager_id,employee_id,notes)
                                        VALUES (?,?,?) ON DUPLICATE KEY UPDATE notes = ?";

const string GET_REVIEW_TYPES_QUERY = "SELECT reviewType FROM Types";

const string GET_REVIEW_DATE_TYPE_QUERY = "SELECT review_date,review_type FROM " +
                                          "Reviews INNER JOIN Contributors "+
                                          "WHERE  Reviews.review_id = Contributors.review_id AND contributor= ? "+
                                          "ORDER BY review_date DESC";

const string READ_REVIEW_DETAILS_QUERY = "SELECT Reviews.review_id,team_name, product_version, product_name, component_name, component_version, review_date, review_type FROM " +
                                         "Reviews INNER JOIN Contributors "+
                                         "WHERE  Reviews.review_id = Contributors.review_id AND contributor= ? "+
                                         "ORDER BY review_date DESC";

const string READ_SINGLE_REVIEW_DETAILS_QUERY = "SELECT team_name, product_version, product_name, component_name, component_version, reporter, review_note, reference, review_date, review_type FROM " +
                                                "Reviews INNER JOIN Contributors "+
                                                "WHERE  Reviews.review_id = Contributors.review_id AND contributor= ? AND Reviews.review_id = ? "+
                                                "ORDER BY review_date DESC";


const string READ_OLD_QSP_DETAILS_QUERY = "SELECT * FROM old_qsp_details WHERE" +
                                          " team_member_email =? ORDER BY start_date DESC";