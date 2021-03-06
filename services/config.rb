###########################################
# User Visible Rule Definitions
###########################################

coreo_aws_advisor_alert "cloudtrail-inventory" do
  action :define
  service :cloudtrail
  # link "http://kb.cloudcoreo.com/mydoc-inventory.html"
  include_violations_in_count false
  display_name "ELB Object Inventory"
  description "This rule performs an inventory on all trails in the target AWS account."
  category "Inventory"
  suggested_action "None."
  level "Informational"
  objectives ["trails"]
  audit_objects ["object.trail_list.name"]
  operators ["=~"]
  alert_when [//]
  id_map "object.trail_list.name"
end

coreo_aws_advisor_alert "cloudtrail-service-disabled" do
  action :define
  service :cloudtrail
  link "http://kb.cloudcoreo.com/mydoc_cloudtrail-service-disabled.html"
  display_name "Cloudtrail Service is disabled"
  description "CloudTrail logging is not enabled for this region. It should be enabled."
  category "Audit"
  suggested_action "Enable CloudTrail logs for each region."
  level "Warning"
  objectives ["trails"]
  formulas ["count"]
  audit_objects ["trail_list"]
  operators ["=="]
  alert_when [0]
  id_map "stack.current_region"
end

coreo_aws_advisor_alert "cloudtrail-no-global-trails" do
  action :define
  service :cloudtrail
  category "jsrunner"
  suggested_action "The metadata for this definition is defined in the jsrunner below. Do not put metadata here."
  level "jsrunner"
  objectives [""]
  audit_objects [""]
  operators [""]
  alert_when [true]
  id_map ""
end

###########################################
# System-Defined (Internal) Rule Definitions
###########################################

coreo_aws_advisor_alert "cloudtrail-trail-with-global" do
  action :define
  service :cloudtrail
  include_violations_in_count false
  link "http://kb.cloudcoreo.com/mydoc_unused-alert-definition.html"
  display_name "CloudCoreo Use Only"
  description "This is an internally defined alert."
  category "Internal"
  suggested_action "Ignore"
  level "Internal"
  objectives ["trails"]
  audit_objects ["trail_list.include_global_service_events"]
  operators ["=="]
  alert_when [true]
  id_map "stack.current_region"
end

###########################################
# Compsite-Internal Resources follow until end
#   (Resources used by the system for execution and display processing)
###########################################

coreo_aws_advisor_cloudtrail "advise-cloudtrail" do
  action :advise
  alerts ${AUDIT_AWS_CLOUDTRAIL_ALERT_LIST}
  regions ${AUDIT_AWS_CLOUDTRAIL_REGIONS}
end

coreo_uni_util_jsrunner "cloudtrail-aggregate" do
  action :run
  json_input '{"composite name":"PLAN::stack_name",
  "plan name":"PLAN::name",
  "number_of_checks":"COMPOSITE::coreo_aws_advisor_cloudtrail.advise-cloudtrail.number_checks",
  "number_of_violations":"COMPOSITE::coreo_aws_advisor_cloudtrail.advise-cloudtrail.number_violations",
  "number_violations_ignored":"COMPOSITE::coreo_aws_advisor_cloudtrail.advise-cloudtrail.number_ignored_violations",
  "violations":COMPOSITE::coreo_aws_advisor_cloudtrail.advise-cloudtrail.report}'
  function <<-EOH
var_regions = "${AUDIT_AWS_CLOUDTRAIL_REGIONS}";

let regionArrayJSON =  var_regions;
let regionArray = regionArrayJSON.replace(/'/g, '"');
regionArray = JSON.parse(regionArray);
let createRegionStr = '';
regionArray.forEach(region=> {
    createRegionStr+= region + ' ';
});

var result = {};
result['composite name'] = json_input['composite name'];
result['plan name'] = json_input['plan name'];
result['regions'] = var_regions;
result['violations'] = {};
var nRegionsWithGlobal = 0;
var nViolations = 0;
for (var key in json_input['violations']) {
  if (json_input['violations'].hasOwnProperty(key)) {
    if (json_input['violations'][key]['violations']['cloudtrail-trail-with-global']) {
      nRegionsWithGlobal++;
    } else {
      nViolations++;
      result['violations'][key] = json_input['violations'][key];
    }
  }
}

var noGlobalsAlert = {};
if (nRegionsWithGlobal == 0) {
  regionArray.forEach(region => {
    nViolations++;
    noGlobalsMetadata =
    {
        'link' : 'http://kb.cloudcoreo.com/mydoc_cloudtrail-trail-with-global.html',
        'display_name': 'Cloudtrail global logging is disabled',
        'description': 'CloudTrail global service logging is not enabled for the selected regions.',
        'category': 'Audit',
        'suggested_action': 'Enable CloudTrail global service logging in at least one region',
        'level': 'Warning',
        'region': region
    };
    noGlobalsAlert =
            { violations:
              { 'cloudtrail-no-global-trails':
              noGlobalsMetadata
              },
              tags: []
            };
    var key = 'selected regions';
    if (result['violations'][region]) {
        result['violations'][region]['violations']['cloudtrail-no-global-trails'] = noGlobalsMetadata;
    } else {
        result['violations'][region] = noGlobalsAlert;
    }
  });

}

result['number_of_violations'] = nViolations;
callback(result);
  EOH
end

coreo_uni_util_variables "cloudtrail-update-advisor-output" do
  action :set
  variables([
       {'COMPOSITE::coreo_aws_advisor_cloudtrail.advise-cloudtrail.report' => 'COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-aggregate.return.violations'}
      ])
end

coreo_uni_util_jsrunner "jsrunner-process-suppression-cloudtrail" do
  action :run
  provide_composite_access true
  json_input 'COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-aggregate.return'
  packages([
               {
                   :name => "js-yaml",
                   :version => "3.7.0"
               }       ])
  function <<-EOH
  var fs = require('fs');
  var yaml = require('js-yaml');
  let suppression;
  try {
      suppression = yaml.safeLoad(fs.readFileSync('./suppression.yaml', 'utf8'));
  } catch(e) {

  }
  coreoExport('suppression', JSON.stringify(suppression));
  var violations = json_input.violations;
  var result = {};
  var file_date = null;
  for (var violator_id in violations) {
      result[violator_id] = {};
      result[violator_id].tags = violations[violator_id].tags;
      result[violator_id].violations = {}
      for (var rule_id in violations[violator_id].violations) {
          is_violation = true;
          result[violator_id].violations[rule_id] = violations[violator_id].violations[rule_id];
          for (var suppress_rule_id in suppression) {
              for (var suppress_violator_num in suppression[suppress_rule_id]) {
                  for (var suppress_violator_id in suppression[suppress_rule_id][suppress_violator_num]) {
                      file_date = null;
                      var suppress_obj_id_time = suppression[suppress_rule_id][suppress_violator_num][suppress_violator_id];
                      if (rule_id === suppress_rule_id) {

                          if (violator_id === suppress_violator_id) {
                              var now_date = new Date();

                              if (suppress_obj_id_time === "") {
                                  suppress_obj_id_time = new Date();
                              } else {
                                  file_date = suppress_obj_id_time;
                                  suppress_obj_id_time = file_date;
                              }
                              var rule_date = new Date(suppress_obj_id_time);
                              if (isNaN(rule_date.getTime())) {
                                  rule_date = new Date(0);
                              }

                              if (now_date <= rule_date) {

                                  is_violation = false;

                                  result[violator_id].violations[rule_id]["suppressed"] = true;
                                  if (file_date != null) {
                                      result[violator_id].violations[rule_id]["suppressed_until"] = file_date;
                                      result[violator_id].violations[rule_id]["suppression_expired"] = false;
                                  }
                              }
                          }
                      }
                  }

              }
          }
          if (is_violation) {

              if (file_date !== null) {
                  result[violator_id].violations[rule_id]["suppressed_until"] = file_date;
                  result[violator_id].violations[rule_id]["suppression_expired"] = true;
              } else {
                  result[violator_id].violations[rule_id]["suppression_expired"] = false;
              }
              result[violator_id].violations[rule_id]["suppressed"] = false;
          }
      }
  }
  var rtn = result;
  
  callback(result);
  EOH
end

coreo_uni_util_jsrunner "jsrunner-process-table-cloudtrail" do
  action :run
  provide_composite_access true
  json_input 'COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-aggregate.return'
  packages([
               {
                   :name => "js-yaml",
                   :version => "3.7.0"
               }       ])
  function <<-EOH
    var fs = require('fs');
    var yaml = require('js-yaml');
    try {
        var table = yaml.safeLoad(fs.readFileSync('./table.yaml', 'utf8'));
    }catch(e) {
  
    }
    coreoExport('table', JSON.stringify(table));
    callback(table);
  EOH
end


coreo_uni_util_notify "advise-cloudtrail-json" do
  action :nothing
  type 'email'
  allow_empty ${AUDIT_AWS_CLOUDTRAIL_ALLOW_EMPTY}
  send_on '${AUDIT_AWS_CLOUDTRAIL_SEND_ON}'
  payload 'COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-aggregate.return'
  payload_type "json"
  endpoint ({
      :to => '${AUDIT_AWS_CLOUDTRAIL_ALERT_RECIPIENT}', :subject => 'CloudCoreo cloudtrail advisor alerts on PLAN::stack_name :: PLAN::name'
  }) 
end

## Create Notifiers
coreo_uni_util_jsrunner "cloudtrail-tags-to-notifiers-array" do
  action :run
  data_type "json"
  packages([
        {
          :name => "cloudcoreo-jsrunner-commons",
          :version => "1.6.0"
        }       ])
  json_input '{ "composite name":"PLAN::stack_name",
                "plan name":"PLAN::name",
                "table": COMPOSITE::coreo_uni_util_jsrunner.jsrunner-process-table-cloudtrail.return,
                "violations": COMPOSITE::coreo_uni_util_jsrunner.jsrunner-process-suppression-cloudtrail.return}'
  function <<-EOH
  
const JSON_INPUT = json_input;
const NO_OWNER_EMAIL = "${AUDIT_AWS_CLOUDTRAIL_ALERT_RECIPIENT}";
const OWNER_TAG = "${AUDIT_AWS_CLOUDTRAIL_OWNER_TAG}";
const ALLOW_EMPTY = "${AUDIT_AWS_CLOUDTRAIL_ALLOW_EMPTY}";
const SEND_ON = "${AUDIT_AWS_CLOUDTRAIL_SEND_ON}";
const AUDIT_NAME = 'cloudtrail';
const TABLES = json_input['table'];
const SHOWN_NOT_SORTED_VIOLATIONS_COUNTER = false;

const WHAT_NEED_TO_SHOWN_ON_TABLE = {
    OBJECT_ID: { headerName: 'AWS Object ID', isShown: true},
    REGION: { headerName: 'Region', isShown: true },
    AWS_CONSOLE: { headerName: 'AWS Console', isShown: true },
    TAGS: { headerName: 'Tags', isShown: true },
    AMI: { headerName: 'AMI', isShown: false },
    KILL_SCRIPTS: { headerName: 'Kill Cmd', isShown: false }
};

const VARIABLES = { NO_OWNER_EMAIL, OWNER_TAG, AUDIT_NAME,
    WHAT_NEED_TO_SHOWN_ON_TABLE, ALLOW_EMPTY, SEND_ON,
    undefined, undefined, SHOWN_NOT_SORTED_VIOLATIONS_COUNTER};

const CloudCoreoJSRunner = require('cloudcoreo-jsrunner-commons');
const AuditCLOUDTRAIL = new CloudCoreoJSRunner(JSON_INPUT, VARIABLES, TABLES);
const notifiers = AuditCLOUDTRAIL.getNotifiers();
callback(notifiers);
EOH
end

## Create rollup String
coreo_uni_util_jsrunner "cloudtrail-tags-rollup" do
  action :run
  data_type "text"
  json_input 'COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-tags-to-notifiers-array.return'
  function <<-EOH
var rollup_string = "";
let rollup = '';
let emailText = '';
let numberOfViolations = 0;
for (var entry=0; entry < json_input.length; entry++) {
    if (json_input[entry]['endpoint']['to'].length) {
        numberOfViolations += parseInt(json_input[entry]['num_violations']);
        emailText += "recipient: " + json_input[entry]['endpoint']['to'] + " - " + "Violations: " + json_input[entry]['num_violations'] + "\\n";
    }
}

rollup += 'number of Violations: ' + numberOfViolations + "\\n";
rollup += 'Rollup' + "\\n";
rollup += emailText;

rollup_string = rollup;
callback(rollup_string);
EOH
end

## Send Notifiers
coreo_uni_util_notify "advise-cloudtrail-to-tag-values" do
  action :${AUDIT_AWS_CLOUDTRAIL_HTML_REPORT}
  notifiers 'COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-tags-to-notifiers-array.return'
end

coreo_uni_util_notify "advise-cloudtrail-rollup" do
  action :${AUDIT_AWS_CLOUDTRAIL_ROLLUP_REPORT}
  type 'email'
  allow_empty ${AUDIT_AWS_CLOUDTRAIL_ALLOW_EMPTY}
  send_on '${AUDIT_AWS_CLOUDTRAIL_SEND_ON}'
  payload '
composite name: PLAN::stack_name
plan name: PLAN::name
COMPOSITE::coreo_uni_util_jsrunner.cloudtrail-tags-rollup.return
  '
  payload_type 'text'
  endpoint ({
      :to => '${AUDIT_AWS_CLOUDTRAIL_ALERT_RECIPIENT}', :subject => 'CloudCoreo cloudtrail advisor alerts on PLAN::stack_name :: PLAN::name'
  })
end

