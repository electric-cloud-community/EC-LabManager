##########################
# step.sync.pl
##########################
use ElectricCommander;
use ElectricCommander::PropDB;
use strict;

$::ec = new ElectricCommander();
$::ec->abortOnError(0);
$::pdb = new ElectricCommander::PropDB($::ec);

$| = 1;

my $lm_config   = "$[connection_config]";
my $deployments = '$[deployments]';

sub main {
    print "LabManager Sync:\n";

    # Validate inputs
    $lm_config =~ s/[^A-Za-z0-9_-]//gixms;

    # unpack request
    my $xPath = XML::XPath->new(xml => $deployments);
    my $nodeset = $xPath->find('//Deployment');

    my $instanceList = "";

    # put request in perl hash
    my $deplist;
    foreach my $node ($nodeset->get_nodelist) {

        # for each deployment
        my $i     = $xPath->findvalue('handle',    $node)->string_value;
        my $s     = $xPath->findvalue('state',     $node)->string_value;    # alive
        my $org   = $xPath->findvalue('Org',       $node)->string_value;
        my $work  = $xPath->findvalue('Workspace', $node)->string_value;
        my $conf  = $xPath->findvalue('Config',    $node)->string_value;
        my $vm_id = $xPath->findvalue('VMId',      $node)->string_value;
        my $vm    = $xPath->findvalue('VM',        $node)->string_value;
        print "Input: $i state=$s\n";
        $deplist->{$i}{state}  = "alive";                                   # we only get alive items in list
        $deplist->{$i}{result} = "alive";
        $deplist->{$i}{org}    = $org;
        $deplist->{$i}{work}   = $work;
        $deplist->{$i}{conf}   = $conf;
        $deplist->{$i}{vm_id}  = $vm_id;
        $deplist->{$i}{vm}     = $vm;
        $instanceList .= "$i\;";
    }

    checkIfAlive($instanceList, $deplist);

    my $xmlout = "";
    addXML(\$xmlout, "<SyncResponse>");
    foreach my $handle (keys %{$deplist}) {
        my $result = $deplist->{$handle}{result};
        my $state  = $deplist->{$handle}{state};

        addXML(\$xmlout, "<Deployment>");
        addXML(\$xmlout, "  <handle>$handle</handle>");
        addXML(\$xmlout, "  <state>$state</state>");
        addXML(\$xmlout, "  <result>$result</result>");
        addXML(\$xmlout, "</Deployment>");
    }
    addXML(\$xmlout, "</SyncResponse>");
    $::ec->setProperty("/myJob/CloudManager/sync", $xmlout);
    print "\n$xmlout\n";
    exit 0;
}

# checks status of instances
# if found to be stopped, it marks the deplist to pending
# otherwise (including errors running api) it assumes it is still running
sub checkIfAlive {
    my ($instances, $deplist) = @_;

    foreach my $handle (keys %{$deplist}) {
        my $org   = $deplist->{$handle}{org};
        my $work  = $deplist->{$handle}{work};
        my $conf  = $deplist->{$handle}{conf};
        my $vm_id = $deplist->{$handle}{vm_id};
        my $vm    = $deplist->{$handle}{vm};

        ### get config state ###
        print("Running LabManager Command \n");
        my $proj = "$[/myProject/projectName]";
        my $proc = "Command";
        my $xPath = $::ec->runProcedure(
                                        "$proj",
                                        {
                                           procedureName   => "$proc",
                                           pollInterval    => 1,
                                           timeout         => 3600,
                                           actualParameter => [{ actualParameterName => "connection_config", value => "$lm_config" }, { actualParameterName => "labmanager_cmd", value => "GetMachine" }, { actualParameterName => "labmanager_cmdargs", value => "machineId=$vm_id" }, { actualParameterName => "labmanager_org", value => "$org" }, { actualParameterName => "labmanager_work", value => "$work" },],
                                        }
                                       );
        if ($xPath) {
            my $code = $xPath->findvalue('//code')->string_value;
            if ($code ne "") {
                my $mesg = $xPath->findvalue('//message')->string_value;
                print "Run procedure returned code is '$code'\n$mesg\n";
                return;
            }
        }
        my $outcome = $xPath->findvalue('//outcome')->string_value;
        my $jobid   = $xPath->findvalue('//jobId')->string_value;
        if (!$jobid) {

            # at this point we have to assume it is still running becaue we could not prove otherwise
            print "could not find jobid of Command job.\n";
            return;
        }
        my $response = $::pdb->getProp("/jobs/$jobid/LabManager/deployed_configs/command_result");
        if ("$response" eq "") {
            print "could not find results of configurations in /jobs/$jobid/LabManager/deployed_configs/command_result\n";
            my $command_error = $::pdb->getProp("/jobs/$jobid/LabManager/deployed_configs/command_error");
            if ($command_error =~ m/Could not find virtual machine in database given the parameters./) {
                print("VM $deplist->{$handle}{vm} in configuration $deplist->{$handle}{conf} stopped\n");
                $deplist->{$handle}{state}  = "pending";
                $deplist->{$handle}{result} = "success";
                $deplist->{$handle}{mesg}   = "VM was manually stopped or failed";
                next;
            }
            return;
        }

        my $respath = XML::XPath->new(xml => "$response");

        #my $nodeset = $respath->find('//GetMachineResult');

        my $name       = $respath->find('//GetMachineResult/name');
        my $isDeployed = $respath->find('//GetMachineResult/isDeployed');
        my $state      = $respath->find('//GetMachineResult/status');

        # deployment specific response

        #print "state $state\n";
        my $err = "success";
        my $msg = "";
        if ("$state" eq "2") {
            print("VM $deplist->{$handle}{vm} in configuration $deplist->{$handle}{conf} still running\n");
            $deplist->{$handle}{state}  = "alive";
            $deplist->{$handle}{result} = "success";
            $deplist->{$handle}{mesg}   = "VM still running";
        }
        else {
            print("VM $deplist->{$handle}{vm} in configuration $deplist->{$handle}{conf} stopped\n");
            $deplist->{$handle}{state}  = "pending";
            $deplist->{$handle}{result} = "success";
            $deplist->{$handle}{mesg}   = "VM was manually stopped or failed";
        }
    }
    return;
}

sub addXML {
    my ($xml, $text) = @_;
    ## TODO encode
    ## TODO autoindent
    $$xml .= $text;
    $$xml .= "\n";
}

main();
