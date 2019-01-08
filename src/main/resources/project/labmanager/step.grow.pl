##########################
# step.grow.pl
##########################
use ElectricCommander;
use ElectricCommander::PropDB;

$::ec = new ElectricCommander();
$::ec->abortOnError(0);

$| = 1;

my $number   = "$[number]";
my $poolName = "$[poolName]";

my $connection_config           = "$[connection_config]";
my $labmanager_config           = "$[labmanager_config]";
my $labmanager_fencedmode       = "$[labmanager_fencedmode]";
my $labmanager_newconfig        = "$[labmanager_newconfig]";
my $labmanager_org              = "$[labmanager_org]";
my $labmanager_work             = "$[labmanager_work]";
my $labmanager_workspace        = "$[labmanager_workspace]";
my $labmanager_state            = "$[labmanager_state]";
my $labmanager_physical_network = "$[labmanager_physical_network]";
my $Tag                         = "$[Tag]";
my $labmanager_version          = "$[labmanager_version]";

my @deparray = split(/\|/, $deplist);

sub main {
    print "LabManager Grow:\n";

    #
    # Validate inputs
    #
    $number                      =~ s/[^0-9]//gixms;
    $poolName                    =~ s/[^A-Za-z0-9_-].*//gixms;
    $connection_config           =~ s/[^A-Za-z0-9_-]//gixms;
    $labmanager_config           =~ s/[^A-Za-z0-9_-]//gixms;
    $labmanager_fencedmode       =~ s/[^0-9]//gixms;
    $labmanager_newconfig        =~ s/[^A-Za-z0-9_-]//gixms;
    $labmanager_org              =~ s/[^A-Za-z0-9_-].*//gixms;
    $labmanager_work             =~ s/[^A-Za-z0-9_-].*//gixms;
    $labmanager_workspace        =~ s/[^A-Za-z0-9_-].*//gixms;
    $labmanager_state            =~ s/[^0-9]//gixms;
    $labmanager_physical_network =~ s/[^A-Za-z0-9_-]//gixms;
    $Tag                         =~ s/[^A-Za-z0-9_-]//gixms;
    $labmanager_version          =~ s/[^0-9].*//gixms;

    my $xmlout = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n";
    addXML(\$xmlout, "<GrowResponse>");

    ### CREATE CONFIGS ###

    $labmanager_version =~ m/([\d]).*/xms;
    my $version = $1;

    my $count = $number;
    my $xPath;
    my $conf_number = '1';
    for (1 .. $count) {
        $conf_number = $_;

        if ($version lt 4) {
            print("Running LabManager Provision\n");
            my $proj = "$[/myProject/projectName]";
            my $proc = "Provision";
            $xPath = $::ec->runProcedure(
                "$proj",
                {
                   procedureName   => "$proc",
                   pollInterval    => 1,
                   timeout         => 3600,
                   actualParameter => [{ actualParameterName => "connection_config", value => "$connection_config" }, { actualParameterName => "labmanager_config", value => "$labmanager_config" }, { actualParameterName => "labmanager_fencedmode", value => "$labmanager_fencedmode" }, { actualParameterName => "labmanager_createresource", value => '1' }, { actualParameterName => "labmanager_newconfig", value => "$labmanager_newconfig-$[jobStepId]-$conf_number" }, { actualParameterName => "labmanager_org", value => "$labmanager_org" }, { actualParameterName => "labmanager_work", value => "$labmanager_work" }, { actualParameterName => "labmanager_workspace", value => "$labmanager_workspace" }, { actualParameterName => "labmanager_state", value => "$labmanager_state" }, { actualParameterName => "labmanager_physical_network", value => "$labmanager_physical_network" }, { actualParameterName => "tag", value => "$Tag" }, { actualParameterName => "results", value => "/myJob/LabManager/deployed_configs/" }, { actualParameterName => "labmanager_pools", value => "$poolName" },],

                }
            );
        }
        else {

            print("Running LabManager Provision4.0\n");
            my $proj = "$[/myProject/projectName]";
            my $proc = "Provision4.0";
            $xPath = $::ec->runProcedure(
                "$proj",
                {
                   procedureName   => "$proc",
                   pollInterval    => 1,
                   timeout         => 3600,
                   actualParameter => [{ actualParameterName => "connection_config", value => "$connection_config" }, { actualParameterName => "labmanager_config", value => "$labmanager_config" }, { actualParameterName => "labmanager_fencedmode", value => "$labmanager_fencedmode" }, { actualParameterName => "labmanager_createresource", value => '1' }, { actualParameterName => "labmanager_newconfig", value => "$labmanager_newconfig-$[jobStepId]-$conf_number" }, { actualParameterName => "labmanager_org", value => "$labmanager_org" }, { actualParameterName => "labmanager_work", value => "$labmanager_work" }, { actualParameterName => "labmanager_workspace", value => "$labmanager_workspace" }, { actualParameterName => "labmanager_state", value => "$labmanager_state" }, { actualParameterName => "labmanager_physical_network", value => "$labmanager_physical_network" }, { actualParameterName => "labmanager_vms_to_deploy", value => "" }, { actualParameterName => "tag", value => "$Tag" }, { actualParameterName => "results", value => "/myJob/LabManager/deployed_configs/" }, { actualParameterName => "labmanager_pools", value => "$poolName" },],

                }
            );

        }

        if ($xPath) {
            my $code = $xPath->findvalue('//code');
            if ($code ne "") {
                my $mesg = $xPath->findvalue('//message');
                print "Run procedure returned code is '$code'\n$mesg\n";
            }
        }
        my $outcome = $xPath->findvalue('//outcome')->string_value;
        if ("$outcome" ne "success") {
            print "LabManager Provision job failed.\n";
            next;

            #exit 1;
        }
        my $jobId = $xPath->findvalue('//jobId')->string_value;
        if (!$jobId) {

            #exit 1;
            next;
        }

        my $depobj = new ElectricCommander::PropDB($::ec, "");
        my $vmList = $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/VMList");
        print "VM list=$vmList\n";
        my @vms = split(/;/, $vmList);
        my $createdList = ();

        foreach my $vm (@vms) {
            addXML(\$xmlout, "<Deployment>");
            addXML(\$xmlout, "<handle>$vm</handle>");
            addXML(\$xmlout, "<hostname>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/resources/$vm/hostName") . "</hostname>");
            addXML(\$xmlout, "<resource>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/resources/$vm/resName") . "</resource>");
            addXML(\$xmlout, "<Config>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/cfgName") . "</Config>");
            addXML(\$xmlout, "<VM>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/resources/$vm/machineName") . "</VM>");
            addXML(\$xmlout, "<VMId>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/resources/$vm/machineID") . "</VMId>");
            addXML(\$xmlout, "<Org>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/resources/$vm/Org") . "</Org>");
            addXML(\$xmlout, "<Workspace>" . $depobj->getProp("/jobs/$jobId/LabManager/deployed_configs/$Tag/resources/$vm/Workspace") . "</Workspace>");
            addXML(\$xmlout, "<results>/jobs/$jobId/LabManager/deployed_configs</results>");
            addXML(\$xmlout, "<tag>$Tag</tag>");
            addXML(\$xmlout, "</Deployment>");
        }
    }

    addXML(\$xmlout, "</GrowResponse>");

    my $prop = "/myJob/CloudManager/grow";
    print "Registering results for $vmList in $prop\n";
    $::ec->setProperty("$prop", $xmlout);
}

sub addXML {
    my ($xml, $text) = @_;
    ## TODO encode
    ## TODO autoindent
    $$xml .= $text;
    $$xml .= "\n";
}

main();
