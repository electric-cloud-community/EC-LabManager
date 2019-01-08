##########################
# attemptConnection.pl
##########################


use ElectricCommander;
use ElectricCommander::PropDB;
use ElectricCommander::PropMod;
use LWP::UserAgent;
use MIME::Base64;

use Carp qw( carp croak );

use constant {
               SUCCESS => 0,
               ERROR   => 1,
             };

## get an EC object
my $ec = ElectricCommander->new();
$ec->abortOnError(0);

my $xpath  = $ec->getFullCredential("credential");
my $errors = $ec->checkAllErrors($xpath);
my $opts;
my $cfgName  = "$[/myJob/config]";
my $projName = "$[/myProject/projectName]";
print "Attempting connection with server\n";
print "-- Authenticating with server --\n";

my $cfg = new ElectricCommander::PropDB($ec, "/projects/$projName/labmanager_cfgs");

# read values from this config
$opts->{config} = $cfgName;
$opts->{labmanager_server}  = $cfg->getCol("$cfgName", "labmanager_server");
$opts->{labmanager_port}    = $cfg->getCol("$cfgName", "labmanager_port");
$opts->{labmanager_user}    = $xpath->findvalue("//userName");
$opts->{labmanager_pass}    = $xpath->findvalue("//password");
$opts->{labmanager_org}     = "";
$opts->{debug}              = $cfg->getCol("$cfgName", "debug");
$opts->{soap_timeout}       = $cfg->getCol("$cfgName", "soap_timeout");

$opts->{connection_config} = $cfgName;
$opts->{labmanager_org} = '';
$opts->{labmanager_work} = '';
$opts->{labmanager_cmd} = 'ListConfigurations';
$opts->{labmanager_cmdargs} = 'configurationType=1';

$opts->{JobStepId} = "$[/myJobStep/jobStepId]";

# Load the actual code into this process
if (!ElectricCommander::PropMod::loadPerlCodeFromProperty($ec, "/myProject/lm_driver/LabManager")) {
    print "Could not load LabManager.pm\n";
    exit 1;
}

# Make an instance of the object, passing in options as a hash
my $gt = LabManager->new($ec, $opts);

$gt->opts->{LMUseInternalAPI} = 1;    # Internal API is used in some commands

$result = $gt->command();


if($gt->opts->{exitcode}) {
    $ec->setProperty("outcome","error");
    my $errMsg = "\nTest connection failed.\n";
    $ec->setProperty("/myJob/configError", $errMsg);
    print $errMsg;

    $ec->deleteProperty("/projects/$projName/labmanager_cfgs/$cfgName");
    $ec->deleteCredential($projName, $cfgName);
    
    exit ERROR;    
} else {
    exit SUCCESS;
}
