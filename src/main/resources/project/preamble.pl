use ElectricCommander;
use File::Basename;
use ElectricCommander::PropDB;
use ElectricCommander::PropMod;
use Encode;
use utf8;

$| = 1;

use constant {
               SUCCESS => 0,
               ERROR   => 1,
             };

# Create ElectricCommander instance
my $ec = new ElectricCommander();
$ec->abortOnError(0);

my $pluginKey  = 'EC-LabManager';
my $xpath      = $ec->getPlugin($pluginKey);
my $pluginName = $xpath->findvalue('//pluginVersion')->value;
print "Using plugin $pluginKey version $pluginName\n";
$opts->{pluginVer} = $pluginName;

if (defined($opts->{connection_config}) && $opts->{connection_config} ne "") {

    my $cfgName = $opts->{connection_config};
    print "Loading config $cfgName\n";

    my $proj = "$[/myProject/projectName]";
    my $cfg = new ElectricCommander::PropDB($ec, "/projects/$proj/labmanager_cfgs");

    if (!defined($cfg) || $cfg eq "") {
        print "Configuration [$cfgName] does not exist\n";
        exit ERROR;
    }

    # Add the option from the connection config
    my %vals = $cfg->getRow($cfgName);
    foreach my $c (keys %vals) {
        print "Adding config $c=$vals{$c}\n";
        $opts->{$c} = $vals{$c};
    }

    # Check that credential item exists
    if (!defined $opts->{credential} || $opts->{credential} eq "") {
        print "Configuration [$cfgName] does not contain a LabManager credential\n";
        exit ERROR;
    }

    # Get user/password out of credential named in $opts->{credential}
    my $xpath = $ec->getFullCredential("$opts->{credential}");
    $opts->{labmanager_user} = $xpath->findvalue("//userName");
    $opts->{labmanager_pass} = $xpath->findvalue("//password");

    # Check for required items
    if (!defined $opts->{labmanager_server} || $opts->{labmanager_server} eq "") {
        print "Configuration [$cfgName] does not contain a LabManager server name\n";
        exit ERROR;
    }
    if (!defined $opts->{labmanager_user} || $opts->{labmanager_user} eq "") {
        print "Credential [$opts->{credential}] does not contain a username\n";
        exit ERROR;
    }
    if (!defined $opts->{labmanager_pass} || $opts->{labmanager_pass} eq "") {
        print "Credential [$opts->{credential}] does not contain a password\n";
        exit ERROR;
    }

    # read values from this config
    $opts->{SoapTimeout} = $cfg->getCol("$cfgName", "soap_timeout");
    $opts->{Debug}       = $cfg->getCol("$cfgName", "debug");

}

$opts->{JobStepId} = "$[/myJobStep/jobStepId]";

# Load the actual code into this process
if (!ElectricCommander::PropMod::loadPerlCodeFromProperty($ec, "/myProject/lm_driver/LabManager")) {
    print "Could not load LabManager.pm\n";
    exit 1;
}

# Make an instance of the object, passing in options as a hash
my $gt = new LabManager($ec, $opts);

