# -----------------------------------------------------------------------------
# Copyright 2005-2010 Electric Cloud Corporation
#
#
# Package
#    LabManager.pm
#
# Purpose
#    A perl library that encapsulates the logic to call procedures from VMWare LabManager SOAP API
#
# Notes
#    The LabManager SOAP server was written in .NET, so there are some
#     incompatibilites with it and the default client behaviour of
#    SOAP::Lite calls.
#
# Dependencies
#    Requires Perl with specific modules
#        Time::Local
#        DateTime
#        ElectricCommander.pm
#        SOAP::Lite
#        ecarguments.pl
#
# The following special keyword indicates that the "cleanup" script should
# scan this file for formatting errors, even though it doesn't have one of
# the expected extensions.
# CLEANUP: CHECK
#
# Copyright (c) 2005-2010 Electric Cloud, Inc.
# All rights reserved
# -----------------------------------------------------------------------------

package LabManager;

# -------------------------------------------------------------------------
# Includes
# -------------------------------------------------------------------------
use ElectricCommander;
use ElectricCommander::PropDB;
use File::Spec;
use FindBin;
use List::Util qw[min];
use Time::Local;
use Data::Dumper;
use DateTime;

use lib "$FindBin::Bin";
use warnings;
use strict;

use Encode;
use utf8;
use open IO => ':encoding(utf8)';

# Clear out maptype since LM server does not support SOAPStruct
use SOAP::Lite (maptype => {});

# -------------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------------
use constant {
    ALWAYS_USE_INTERNAL_API => 1,    # 1 to use only the internal API, 0 to use both

    WORKSPACECONFIGS => 1,
    LIBRARYCONFIGS   => 2,

    ACTION_ON             => 1,
    ACTION_OFF            => 2,
    ACTION_SUSPEND        => 3,
    ACTION_RESUME         => 4,
    ACTION_RESET          => 5,
    ACTION_SNAPSHOT       => 6,
    ACTION_REVERT         => 7,
    ACTION_SHUTDOWN       => 8,
    ACTION_FORCE_UNDEPLOY => 14,

    OFF   => 1,
    TRUE  => 1,
    FALSE => 0,

    FENCE_NONE        => 1,
    FENCE_BLOCK_INOUT => 2,
    FENCE_ALLOW_OUT   => 3,
    FENCE_ALLOW_INOUT => 4,

    LM_TRUE  => "true",
    LM_FALSE => "false",

    DEFAULT_PINGTIMEOUT => 300,
    DEFAULT_SOAPTIMEOUT => 600,
    DEFAULT_LMPORT      => "443",
    DEFAULT_DEBUG       => 2,
    DEFAULT_LOCATION    => "/myJob/LabManager/deployed_configs",
    DEFAULT_SLEEP       => 5,

    LM_API          => "/LabManager/SOAP/LabManager.asmx",
    LM_INTERNAL_API => "/LabManager/SOAP/LabManagerInternal.asmx",

    SUCCESS => 0,
    ERROR   => 1,
    SOAP_ERROR   => 500,

    BRIDGED_NETWORK => 100,

    RETRY_COUNT        => 0,
    RETRY_INTERVAL     => 1,
    MAX_RETRIES        => 10,
    MAX_RETRY_INTERVAL => 10,

    ALIVE     => 1,
    NOT_ALIVE => 0,
             };

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------

$::gProgramName = "lmintegration";    # program name for errors
@::gLoadFiles   = ();                 # additional perl files to load
$::gMode        = "";                 # mode (provision, cleanup)
$::gVersion     = 0;                  # --version specified

###############################
# new - Object constructor for LabManager
#
# Arguments:
#   cmdr - ElectricCommander object
#   opts - hash
#
# Returns:
#   none
#
###############################
sub new {
    my $class = shift;
    my $self = {
                 _cmdr => shift,
                 _opts => shift,
               };
    bless $self, $class;
}

###############################
# myCmdr - Get ElectricCommander instance
#
# Arguments:
#   none
#
# Returns:
#   ElectricCommander instance
#
###############################
sub myCmdr {
    my ($self) = @_;
    return $self->{_cmdr};
}

###############################
# opts - Get opts hash
#
# Arguments:
#   none
#
# Returns:
#   opts hash
#
###############################
sub opts {
    my ($self) = @_;
    return $self->{_opts};
}

###############################
# checkOption - Check option depending on flags
#
# Arguments:
#   option - name of the option
#   flags - requirements to check
#
# Returns:
#   0 - Success
#   1 - Error
#
###############################
sub checkOption {
    my ($self, $option, $flags) = @_;

    if (defined($self->opts->{$option})) {
        if ($flags =~ /noblank/ && $self->opts->{$option} eq "") {
            $self->debugMsg(0, "required option $option is blank");
            return ERROR;
        }
        elsif ($self->opts->{$option} eq "") {
            $self->opts->{$option} = "";
        }
    }
    else {
        if ($flags =~ /required/) {
            $self->debugMsg(0, "required option $option not found");
            return ERROR;
        }
    }
    return SUCCESS;
}

###############################
# checkValidLocation - Check if location specified in PropPrefix is valid
#
# Arguments:
#   none
#
# Returns:
#   0 - Success
#   1 - Error
#
###############################
sub checkValidLocation {
    my ($self) = @_;
    my $location = "/test-" . $self->opts->{JobStepId};

    # Test set property in location
    my $result = $self->setProp($location, "Test property");
    if (!defined($result) || $result eq "") {
        $self->debugMsg(0, "Invalid location: " . $self->opts->{PropPrefix});
        return ERROR;
    }

    # Test get property in location
    $result = $self->getProp($location);
    if (!defined($result) || $result eq "") {
        $self->debugMsg(0, "Invalid location: " . $self->opts->{PropPrefix});
        return ERROR;
    }

    # Delete property
    $result = $self->deleteProp($location);
    return SUCCESS;
}

###############################
# ecode - Get exit code
#
# Arguments:
#   none
#
# Returns:
#   exit code number
#
###############################
sub ecode {
    my ($self) = @_;
    return $self->opts()->{exitcode};
}

###############################
# myProp - Get PropDB
#
# Arguments:
#   none
#
# Returns:
#   PropDB
#
###############################
sub myProp {
    my ($self) = @_;
    return $self->{_props};
}

###############################
# setProp - Use stored property prefix and PropDB to set a property
#
# Arguments:
#   location - relative location to set the property
#   value    - value of the property
#
# Returns:
#   setResult - result returned by PropDB->setProp
#
###############################
sub setProp {
    my ($self, $location, $value) = @_;
    my $setResult = $self->myProp->setProp($self->opts->{PropPrefix} . $location, $value);
    return $setResult;
}

###############################
# getProp - Use stored property prefix and PropDB to get a property
#
# Arguments:
#   location - relative location to get the property
#
# Returns:
#   getResult - property value
#
###############################
sub getProp {
    my ($self, $location) = @_;
    my $getResult = $self->myProp->getProp($self->opts->{PropPrefix} . $location);
    return $getResult;
}

###############################
# deleteProp - Use stored property prefix and PropDB to delete a property
#
# Arguments:
#   location - relative location of the property to delete
#
# Returns:
#   delResult - result returned by PropDB->deleteProp
#
###############################
sub deleteProp {
    my ($self, $location) = @_;
    my $delResult = $self->myProp->deleteProp($self->opts->{PropPrefix} . $location);
    return $delResult;
}

###############################
# Initialize - Initializes object options
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub Initialize {
    my ($self) = @_;

    $self->{_props} = new ElectricCommander::PropDB($self->myCmdr(), "");

    if (!defined($self->opts->{debug})) {
        $self->opts->{debug} = DEFAULT_DEBUG;
    }

    #$self->debugMsg(0, "Debug Level: " . $self->opts->{debug});
    $self->opts->{exitcode} = SUCCESS;

    if (!defined($self->opts->{labmanager_port})) {
        $self->opts->{labmanager_port} = DEFAULT_LMPORT;
    }

    if (!defined($self->opts->{PingTimeout})) {
        $self->opts->{PingTimeout} = DEFAULT_PINGTIMEOUT;    # timeout to wait for agent ping in secs
    }

    # Set initial values to proxy depending on the api
    $self->initializeProxy;

    # timeout for soap call return. 5 min by def
    if (!defined($self->opts->{SoapTimeout})) {
        $self->opts->{SoapTimeout} = DEFAULT_SOAPTIMEOUT;
    }

    #$self->debugMsg(0, "Soap Timeout: " . $self->opts->{SoapTimeout});

    if ($self->opts->{debug} >= 5) {
        foreach my $o (sort keys %{ $self->opts }) {
            $self->debugMsg(5, " option {$o}=" . $self->opts->{$o});
        }
    }

}

###############################
# initializePropPrefix - Initialize PropPrefix value and check valid location
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub initializePropPrefix {
    my ($self) = @_;

    # setup the property sheet where information will be exchanged
    if (!defined($self->opts->{results}) || $self->opts->{results} eq "") {
        if ($self->opts->{JobStepId} ne "1") {
            $self->opts->{results} = DEFAULT_LOCATION;    # default location to save properties
        }
        else {
            $self->debugMsg(0, "Must specify property sheet location when not running in job");
            $self->opts->{exitcode} = ERROR;
            return;
        }
    }
    $self->opts->{PropPrefix} = $self->opts->{results};
    if (defined($self->opts->{Tag}) && $self->opts->{Tag} ne "") {
        $self->opts->{PropPrefix} .= "/" . $self->opts->{Tag};
    }

    # test that the location is valid
    if ($self->checkValidLocation) {
        $self->opts->{exitcode} = ERROR;
        return;
    }
}

###############################
# initializeDestinationPropPrefix - Initialize DestinationPropPrefix value and check valid location
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub initializeDestinationPropPrefix {
    my ($self) = @_;

    # Set default destination results location if not set
    if (!defined($self->opts->{destination_results})
        || $self->opts->{destination_results} eq "")
    {
        if ($self->opts->{JobStepId} ne "1") {
            $self->opts->{destination_results} = DEFAULT_LOCATION;    # default location to save properties
        }
        else {
            $self->debugMsg(0, "Must specify destination property sheet location when not running in job");
            $self->opts->{exitcode} = ERROR;
            return;
        }
    }
    $self->opts->{DestinationPropPrefix} = $self->opts->{destination_results};
    if (defined($self->opts->{destination_tag})
        && $self->opts->{destination_tag} ne "")
    {
        $self->opts->{DestinationPropPrefix} .= "/" . $self->opts->{destination_tag};
    }

    # store $opts->{PropPrefix} in a temporal variable to check valid location of destination location
    my $propPrefix = $self->opts->{PropPrefix};
    $self->opts->{PropPrefix} = $self->opts->{DestinationPropPrefix};

    # check valid location of destination location
    if ($self->checkValidLocation) {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    # put value of $opts->{PropPrefix} back
    $self->opts->{PropPrefix} = $propPrefix;
}

###############################
# initializeProxy - Initializes opts->{Proxy} depending on the API to use (base or internal)
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub initializeProxy {
    my ($self) = @_;

    # Set the API type
    my $labManagerAPI = LM_API;
    $labManagerAPI = LM_INTERNAL_API
    if ($self->opts->{LMUseInternalAPI} or ALWAYS_USE_INTERNAL_API);

    $self->opts->{Proxy} = "";

    # if protocol passed in, do not add one
    if (   substr($self->opts->{labmanager_server}, 0, 5) eq "http:"
        or substr($self->opts->{labmanager_server}, 0, 4) eq "tcp:"
        or substr($self->opts->{labmanager_server}, 0, 6) eq "https:")
    {
        $self->opts->{Proxy} = "";
    }
    else {
        $self->opts->{Proxy} = "https://";
    }

    $self->opts->{Proxy} .= $self->opts->{labmanager_server};
    if (defined($self->opts->{labmanager_port})
        && $self->opts->{labmanager_port} ne "")
    {
        $self->opts->{Proxy} .= ":" . $self->opts->{labmanager_port};
    }

    $self->opts->{Proxy} .= $labManagerAPI;
    $self->debugMsg(2, "Initialize server proxy=" . $self->opts->{Proxy});
}

###############################
# command - run a command from VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   results from command as xml
#
###############################
sub command {
    my ($self) = @_;
    
    my @result;
    
    $self->opts->{LMUseInternalAPI} = TRUE;    # Internal API is used in some commands
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    my %args;
    if ($self->opts->{LoadFromFile}) {
        %args = %{ $self->opts->{labmanager_cmdargs} };
    }
    else {
        my @arg;
        if (defined($self->opts->{labmanager_cmdargs})
            && $self->opts->{labmanager_cmdargs} ne "")
        {
            foreach my $p (split(" ", $self->opts->{labmanager_cmdargs})) {
                @arg = split("=", $p);
                $args{ $arg[0] } = $arg[1];
            }
        }
    }

    $self->debugMsg(5, "command details");
    $self->debugMsg(5, " " . $self->opts->{labmanager_cmd});
    foreach my $c (sort keys %args) {
        $self->debugMsg(5, " $c=" . $args{$c});
    }

    # pass parameters from command line to worker function    
    my (%result) = $self->CallLabManager($self->opts->{labmanager_cmd}, %args);


    # process errors
    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: " . $result{"faultcode"} . " " . $result{"faultstring"} . " " . $result{"faultdetail"});
        $self->opts->{exitcode} = $result{"faultcode"};
        $self->setProp("/command_error", $result{"faultstring"});
        return;
    }

    # if no return type we are done
    if ($result{"retType"} eq "NONE") {
        return;
    }

    # if single value return, print as XML
    if ($result{"retType"} eq "SCALAR") {
        my $name  = @{ $result{"retRec"} }[0];
        my $value = $result{"value"};
        push(@result, qq{<result>});
        print "<$name>$value</$name>\n";
        push(@result, qq{<$name>$value</$name>});
        push(@result, qq{</result>});
        my $res_xml = join("\n", @result);
        
        $self->setProp("/command_result", $res_xml);
        return;
    }

    #print Data::Dumper->Dump([%result], [qw(result)]);

    # if records, find fields and print XML
    if ($result{"retType"} eq "RECORD") {
        my $name   = $result{"retFld"};
        my @values = @{ $result{"value"} };
        push(@result, qq{<result>});
        foreach my $node (@values) {
            print "<$name>\n";
            push(@result, qq{<$name>});
            my @fields = @{ $result{"retRec"} };
            foreach my $fld (@fields) {
                my $value = $node->{"$fld"};
                if (!defined($value)) { $value = ""; }
                print "<$fld>$value</$fld>\n";
                push(@result, qq{<$fld>$value</$fld>});
            }
            
            print "</$name>\n";
            push(@result, qq{</$name>});
        }
        push(@result, qq{</result>});
        my $res_xml = join("\n", @result);

        $self->setProp("/command_result", $res_xml);
        return;
    }    
}

###############################
# provision - Provision a configuration using VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub provision {

    my ($self) = @_;

    
    $self->debugMsg(1, '---------------------------------------------------------------------');
    
    $self->opts->{LMUseInternalAPI} = TRUE;    # Internal API is used in some calls
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    if (   $self->checkOption("labmanager_config", "required noblank")
        || $self->checkOption("labmanager_createresource", "required noblank")
        || $self->checkOption("labmanager_pools",          "required")
        || $self->checkOption("labmanager_fencedmode",     "required")
        || $self->checkOption("labmanager_newconfig",      "required")
        || $self->checkOption("labmanager_workspace",      "required"))
    {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    #-----------------------------------
    # process config
    #-----------------------------------
    my %result;    # used for results from LM calls
    my $firstConfiguration = 1;
    my $setResult;
    $self->debugMsg(1, "---------------------------------------------------------------------");
    $self->debugMsg(1, "Config");
    $self->debugMsg(1, "  Name:[" . $self->opts->{labmanager_config} . "]");
    $self->debugMsg(1, "  Create Resouces:[" . $self->opts->{labmanager_createresource} . "]");
    $self->debugMsg(1, "  Pools:[" . $self->opts->{labmanager_pools} . "]");

    #-------------------------------------
    # Get Library ID using name
    #-------------------------------------
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, "Looking up Configuration name in library");
    %result = $self->CallLabManager("ListConfigurations", ("configurationType" => LIBRARYCONFIGS));
    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: listing configurations ");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }
    my $cfgId = 0;
    foreach my $node (@{ $result{"value"} }) {
        if ($node->{"name"} eq $self->opts->{labmanager_config}) {
            $self->debugMsg(1, "Found Configuration");
            $self->debugMsg(1, "Name:" . $node->{"name"});
            $self->debugMsg(1, "ID:" . $node->{"id"});
            $self->debugMsg(1, "Desc:" . $node->{"description"});
            $self->debugMsg(1, "Public:" . $node->{"isPublic"});
            $self->debugMsg(1, "Deployed:" . $node->{"isDeployed"});
            $self->debugMsg(1, "Fence Mode:" . $node->{"fenceMode"});
            $self->debugMsg(1, "Type:" . $node->{"type"});
            $self->debugMsg(1, "Owner:" . $node->{"owner"});
            $self->debugMsg(1, "Date Created:" . $node->{"dateCreated"});
            $cfgId = $node->{"id"};
            last;
        }
    }

    # Check if configuration exists
    if ($cfgId == 0) {
        $self->debugMsg(0, "Error: library configuraiton '" . $self->opts->{labmanager_config} . "' does not exist in the specified organization");
        $self->opts->{exitcode} = ERROR;
        return;
    }

    #-------------------------------------
    # Check config out to Workspace
    #-------------------------------------
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, 'Checking Config out to Workspace');

    # If user did not specify a new cfg name, make a unique one
    my $newName = $self->opts->{labmanager_newconfig};
    if ($newName eq '') {
        $newName = $self->opts->{labmanager_config} . '-' . $self->opts->{JobStepId};
    }

    # Configuration checkouts can fail because the "object is busy" --
    # retry a few times, if that's the case.
    my $retryCount       = RETRY_COUNT;
    my $retryInterval    = RETRY_INTERVAL;
    my $maxRetries       = MAX_RETRIES;
    my $maxRetryInterval = MAX_RETRY_INTERVAL;

    do {

        # If this is a retry, sleep first
        if ($retryCount++ > 0) {
            $retryInterval = min($maxRetryInterval, $retryInterval * 2);
            $self->debugMsg(1, "$newName is busy, will retry after $retryInterval seconds (attempt #$retryCount)");
            sleep $retryInterval;
        }

        # Check which procedure is running (Provision or Provision4.0), and whether a VM list was specified
        if (defined($self->opts->{labmanager_vms_to_deploy}) && $self->opts->{labmanager_version} eq "4" #&& $self->opts->{labmanager_vms_to_deploy} ne ""   ### if eq "" should copy all machines
        )
        {
            %result = $self->cloneConfig($cfgId, $newName);
           if ($self->opts->{exitcode}) { return; }
       }
       else {
            %result = $self->CallLabManager("ConfigurationCheckout", (configurationId => $cfgId, workspaceName => $newName));
        }

        # Certain errors are retryable -- if not, set the retryCount to
        # max so we don't retry
        if (   $result{"faultcode"} && $result{"faultstring"} !~ /The object you selected is currently busy/)
        {
            $retryCount = $maxRetries;
        }

    } while ($result{"faultcode"} && $retryCount < $maxRetries);

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: checking out configuration " . $newName);
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my $workspaceId = $result{"value"};

    if ($result{"faultcode"} or $workspaceId le 0) {
        $self->debugMsg(0, "Error: could not checkout " . $cfgId . " to " . $newName);
        $self->debugMsg(0, "       " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    #-------------------------------------
    # Record the workspace ID in properties
    #-------------------------------------
    $self->debugMsg(1, "Recording ID($workspaceId) in properties");
    $setResult = $self->setProp("/cfgId", $workspaceId);
    if ($setResult eq "") {
        $self->debugMsg(0, "Error: recording LabManager workspace ID");
        $self->debugMsg(0, "Error: " . $setResult);
        %result = $self->CallLabManager("ConfigurationDelete", ("configurationId" => $workspaceId));
        $self->opts->{exitcode} = ERROR;
        return;
    }
    $setResult = $self->setProp("/cfgName", $newName);

    #-------------------------------------
    # Set configuration state to public or private
    #-------------------------------------
    $self->setState($workspaceId);

    #-------------------------------------
    # Deploy the configuration
    #-------------------------------------
    my $res = $self->deployConfiguration($workspaceId, $newName);
    if ($res eq ERROR) { return; }

    #-------------------------------------
    # Create resources and save information in properties
    #-------------------------------------
    $self->createResources($workspaceId, $newName);
$self->debugMsg(0, "---------------------------------------------");
    $self->debugMsg(0, "Provision finished");
}

###############################
# cloneConfig - Clone a LabManager Configuration to Workspace, specifying a subset of the VMs to copy
#
# Arguments:
#   cfgId         - ID of the Configuration to clone
#   newConfigName - Name of the new Configuration
#
# Returns:
#   result - result of calling LabManager method LibraryCloneToWorkspace
#
###############################
sub cloneConfig {
    my ($self, $cfgId, $newConfigName) = @_;

    my @vmsToCopy = split(/;/, $self->opts->{labmanager_vms_to_deploy});

    #-------------------------------------
    # Iterate machines in configuration
    #-------------------------------------
    my %result = $self->CallLabManager("ListMachines", ("configurationId" => $cfgId,));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: " . $result{"faultcode"} . " " . $result{"faultstring"} . " " . $result{"faultdetail"});
        $self->opts->{exitcode} = $result{"faultcode"};
        return;
    }

    my @machines = @{ $result{"value"} };

    my @machine_data;
    my $storage;

    my @vmCopyData = ();
    foreach my $machine (@machines) {
        $self->debugMsg(1, "Name:" . $machine->{"name"});
        $self->debugMsg(1, "DS:" . $machine->{"DatastoreNameResidesOn"});
        if ((grep { $_ eq $machine->{"name"} } @vmsToCopy) || ($self->opts->{labmanager_vms_to_deploy} eq "")) {
            push(
                 @vmCopyData,
                 {
                    'VMCopyData' => {
                                      'machine'           => $machine,
                                      'storageServerName' => $machine->{"DatastoreNameResidesOn"}
                                    }
                 }
                );

        }

    }

    if (!@vmCopyData) {
        $self->debugMsg(0, "Error: there are no machines to copy");
        $self->opts->{exitcode} = ERROR;

    }

    #Get Organization ID using name
    if ($self->opts->{labmanager_org} ne '') {
        $self->debugMsg(5, "---------------------------------------------");
        $self->debugMsg(5, 'Getting ' . $self->opts->{labmanager_org} . ' organization ID');
        %result = $self->CallLabManager("GetOrganizationByName", ("organizationName" => $self->opts->{labmanager_org}));
    }
    else {
        $self->debugMsg(5, "---------------------------------------------");
        $self->debugMsg(5, 'Getting current organization ID');
        %result = $self->CallLabManager("GetCurrentOrganization");
    }

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: fetching Organization ");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my $orgId = $result{"value"}[0]->{"Id"};
    $self->debugMsg(5, 'OrgID: ' . $orgId);

    # Fetch Workspace ID
    $self->debugMsg(5, "---------------------------------------------");
    $self->debugMsg(5, 'Getting ' . $self->opts->{labmanager_org} . ' organization workspaces');
    %result = $self->CallLabManager("GetOrganizationWorkspaces", ("organizationId" => $orgId));
    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: fetching workspace ");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }
    my $workspaceID = 0;
    foreach my $node (@{ $result{"value"} }) {

        if ($node->{"Name"} eq $self->opts->{labmanager_work}) {
            $workspaceID = $node->{"Id"};
            last;
        }
    }

    
    $self->debugMsg(5, "---------------------------------------------");
    %result = $self->CallLabManager(
                                    "LibraryCloneToWorkspace",
                                    (
                                     "libraryId"                  => $cfgId,
                                     "destWorkspaceId"            => $workspaceID,
                                     "isNewConfiguration"         => LM_TRUE,
                                     "newConfigName"              => $newConfigName,
                                     "description"                => "From API",
                                     "copyData"                   => \@vmCopyData,
                                     "existingConfigId"           => 0,
                                     "isFullClone"                => LM_FALSE,
                                     "storageLeaseInMilliseconds" => 2592000000
                                    )
                                   );

    return (%result);
}


###############################
# deploy - Initialize and call deployConfiguration
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub deploy {
    my ($self) = @_;

    $self->opts->{LMUseInternalAPI} = TRUE;
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }

    # Get configuration ID
    my $cfgId = $self->getConfigurationID($self->opts->{labmanager_config});
    if ($self->opts->{exitcode}) { return; }

    # Call procedure to deploy the configuration
    $self->deployConfiguration($cfgId, $self->opts->{labmanager_config});
    if ($self->opts->{exitcode}) { return; }

    $self->debugMsg(0, "Configuration successfully deployed");
}

###############################
# deployConfiguration - Deploy and start a configuration
#
# Arguments:
#   cgfId - configuration ID
#   cfgName - configuration name
#
# Returns:
#   0 - success
#   1 - error
#
###############################
sub deployConfiguration {
    my ($self, $cgfId, $cfgName) = @_;

    my %result;

    # Set up the flag for bridging the virtual networks to
    #   the default physical network.  For now, this is based
    #   on a special value of the Fence Mode
    my $bridgeToPhysical = ($self->opts->{labmanager_fencedmode} == BRIDGED_NETWORK);

    #-------------------------------------
    # Find Virtual Networks
    #   (only if we are going to bridge them)
    #-------------------------------------
    my @virtualNetworkIDs = ();
    if ($bridgeToPhysical) {

        $self->debugMsg(1, "Finding Virtual Networks");
        %result = $self->CallLabManager(
                                        "ConfigurationGetNetworks",
                                        (
                                         "configID" => $cgfId,
                                         "physical" => LM_FALSE
                                        )
                                       );

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: finding virtual networks " . $cfgName);
            $self->debugMsg(0, "    " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return ERROR;
        }

        #  The return from this call is not a record, just an array of strings
        foreach my $networkId (@{ $result{"value"} }) {
            $self->debugMsg(1, "Found Virtual Network - Network ID:" . $networkId);
            push(@virtualNetworkIDs, $networkId);
        }
    }

    #-------------------------------------
    # Calc the ID of the physical network
    #   (only if we are going to bridge to it)
    #-------------------------------------
    my $physicalNetworkID = '';
    my %networkNamesAndIds;
    if (    $bridgeToPhysical
        and @virtualNetworkIDs > 0)
    {

        #-------------------------------------
        # Get the names of all physical networks
        #  Do this first to print the list
        #-------------------------------------
        $self->debugMsg(1, "List networks");
        %result = $self->CallLabManager("ListNetworks");
        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: retrieving list of networks");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return ERROR;
        }

        my @networks = @{ $result{"value"} };
        foreach my $network (@networks) {

            # only look at physical networks
            next if ($network->{"IsPhysical"} ne "true");

            # get names and ids
            my $networkName = $network->{"Name"};
            my $networkID   = $network->{"NetID"};
            $networkNamesAndIds{$networkName} = $networkID;
            $self->debugMsg(0, "Physical Network Name: $networkName  NetID: $networkID");
        }

        # If the user entered an integer - just use it
        if ($self->opts->{labmanager_physical_network} =~ /^\d+$/) {
            $physicalNetworkID = $self->opts->{labmanager_physical_network};
            $self->debugMsg(1, "Using NetID: $physicalNetworkID");

        }
        elsif (defined $networkNamesAndIds{ $self->opts->{labmanager_physical_network} }) {

            # User entered a name that matches - use the NetID
            $physicalNetworkID = $networkNamesAndIds{ $self->opts->{labmanager_physical_network} };
            $self->debugMsg(1, "Using Network Name: $self->opts->{labmanager_physical_network}  NetID: $physicalNetworkID");

        }
        else {

            # Get the default physical network (based on the user/organization)
            $self->debugMsg(1, "Get default physical network");
            %result = $self->CallLabManager("GetDefaultPhysicalNetwork");

            if ($result{"faultcode"}) {
                $self->debugMsg(0, "Error: retrieving LabManager default physical network ");
                $self->debugMsg(0, "    " . $result{"faultstring"});
                $self->opts->{exitcode} = ERROR;
                return ERROR;
            }

            $physicalNetworkID = $result{"value"};
            $self->debugMsg(1, "Using Default NetID: $physicalNetworkID");
        }
    }

    #-------------------------------------
    # Deploy the configuration
    #-------------------------------------
    if (    $bridgeToPhysical
        and $physicalNetworkID
        and @virtualNetworkIDs > 0)
    {
        $self->debugMsg(1, "---------------------------------------------");
        $self->debugMsg(1, "Deploying the configuration with bridging of networks");
        my @bridgeNetworkOptions = ();

        # Construct array of options, 1 per virtual network
        foreach my $virtualNetworkID (@virtualNetworkIDs) {
            push(
                 @bridgeNetworkOptions,
                 {
                    "BridgeNetworkOption" => {
                                               "configuredNetID" => $virtualNetworkID,
                                               "DeployFenceMode" => "FenceAllowInAndOut",
                                               "externalNetID"   => $physicalNetworkID,
                                             }
                 }
                );
        }

        # Use the Internal form of the API call to bridge the networks
        %result = $self->CallLabManager(
                                        "ConfigurationDeployEx",
                                        (
                                         "configurationId"      => $cgfId,
                                         "honorBootOrder"       => LM_FALSE,
                                         "startAfterDeploy"     => LM_TRUE,
                                         "fenceNetworkOptions"  => [],
                                         "bridgeNetworkOptions" => \@bridgeNetworkOptions,
                                        )
                                       );

        # Check the result
        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: deploying LabManager workspace " . $cfgName);
            $self->debugMsg(0, "    " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return ERROR;
        }
    }
    else {

        # Set the fence mode.  If bridging was requested, but
        #  there are no networks to bridge, default to allow in/out
        $self->debugMsg(1, "Deploying the configuration");
        my $fenceMode = FENCE_ALLOW_INOUT;
        if (    $self->opts->{labmanager_fencedmode} > 0
            and $self->opts->{labmanager_fencedmode} < 100)
        {
            $fenceMode = $self->opts->{labmanager_fencedmode};
        }

        # Use Documented form of the API if not bridging
        %result = $self->CallLabManager(
                                        "ConfigurationDeploy",
                                        (
                                         "configurationId" => $cgfId,
                                         "isCached"        => LM_FALSE,
                                         "fenceMode"       => $fenceMode
                                        )
                                       );

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: deploying LabManager workspace " . $cfgName);
            $self->debugMsg(0, "    " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return ERROR;
        }
    }

    #-------------------------------------
    # Start the machines
    #-------------------------------------
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, "Starting the configuration");
    %result = $self->CallLabManager(
                                    "ConfigurationPerformAction",
                                    (
                                     "configurationId" => $cgfId,
                                     "action"          => ACTION_ON,
                                    )
                                   );

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: starting LabManager workspace " . $cfgName);
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return ERROR;
    }
    return SUCCESS;
}

###############################
# setState - Set the state of a configuration to public or private
#
# Arguments:
#   cgfId - configuration ID
#
# Returns:
#   none
#
###############################
sub setState {
    my ($self, $cgfId) = @_;

    my %result;
    my $configurationState;
    if ($self->opts->{labmanager_state}) {
        $configurationState = 'public';
    }
    else {
        $configurationState = 'private';
    }
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, 'Setting configuration state to ' . $configurationState);
    %result = $self->CallLabManager(
                                    "ConfigurationSetPublicPrivate",
                                    (
                                     "configurationId" => $cgfId,
                                     "isPublic"        => $self->opts->{labmanager_state},
                                    )
                                   );

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: setting LabManager configuration state");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }
}

###############################
# createResourcesFromConfiguration - Initialize and call createResources
#
# Arguments:
#   cgfId - configuration ID
#   cfgName - configuration name
#
# Returns:
#   none
#
###############################
sub createResourcesFromConfiguration {
    my ($self) = @_;

    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    # Get configuration ID
    my $cfgId = $self->getConfigurationID($self->opts->{labmanager_config});
    if ($self->opts->{exitcode}) { return; }

    # Call procedure to deploy the configuration
    $self->createResources($cfgId, $self->opts->{labmanager_config});
    if ($self->opts->{exitcode}) { return; }

    $self->debugMsg(0, "Successfully created resources for virtual machines in configuration " . $self->opts->{labmanager_config});
}

###############################
# createResources - Create Commander resources and save information in properties
#
# Arguments:
#   cgfId - configuration ID
#   cfgName - configuration name
#
# Returns:
#   none
#
###############################
sub createResources {
    my ($self, $cgfId, $cfgName) = @_;

    my %result;
    my $setResult;
    my @vmlist         = ();
    my %failedMachines = ();
    my $instlist       = q{};

    if (defined($self->opts->{labmanager_vmlist})
        and $self->opts->{labmanager_vmlist} ne "")
    {
        @vmlist = split(/;/, $self->opts->{labmanager_vmlist});
    }

    #-------------------------------------
    # Record resource names created
    # If resources, create Commander Resources
    #-------------------------------------
    # Append a generated pool name to any specified
    my $pool      = $self->opts->{labmanager_pools} . " EC-" . $self->opts->{JobStepId};
    my $workspace = $self->opts->{labmanager_workspace};

    # Enumerate all machines in this configuration
    $self->debugMsg(5, "---------------------------------------------");
    %result = $self->CallLabManager("ListMachines", ("configurationId" => $cgfId));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: listing machines");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my @machines = @{ $result{"value"} };

    # For each machine, create a resource
    my $numResources = 0;
    foreach my $machine (@machines) {
        $numResources += 1;

        # Do this only for procedure CreateResourcesFromConfiguration
        if (defined($self->opts->{labmanager_vmlist})
            and $self->opts->{labmanager_vmlist} ne "")
        {
            if (!grep { $self->trim($_) eq $machine->{"name"} } @vmlist) {
                next;
            }
        }

        my $propertyName = $cfgName . "-" . $numResources;
        my $machineName  = $cfgName . '_' . $machine->{"name"};
        $machineName =~ s/ /_/g;
        $machineName =~ s/\//_/g;

        my $ipaddr = $machine->{"externalIP"} || "";
        if ($self->opts->{labmanager_createresource} eq "1") {

            if (!defined($machine->{"externalIP"})
                || $machine->{"externalIP"} eq "")
            {
                $ipaddr = $machine->{"name"};
                $machine->{"externalIP"} = $machine->{"internalIP"};
            }
            $self->debugMsg(1, "---------------------------------------------");
            $self->debugMsg(1, "Creating resource for machine:" . $machine->{"name"});
            $self->debugMsg(1, "Resource Name:" . $machineName);
            $self->debugMsg(1, "ID:" . $machine->{"id"});
            $self->debugMsg(1, "Desc:" . $machine->{"description"});
            $self->debugMsg(1, "Deployed:" . $machine->{"isDeployed"});
            $self->debugMsg(1, "Internal IP:" . $machine->{"internalIP"});
            $self->debugMsg(1, "External IP:" . $machine->{"externalIP"});
            $self->debugMsg(1, "Status:" . $machine->{"status"});

            #-------------------------------------
            # Create the resource
            #-------------------------------------
            $self->debugMsg(1, "Creating resource ($ipaddr)");
            my $cmdrresult = $self->myCmdr()->createResource(
                                                             $machineName,
                                                             {
                                                                description   => "LabManager provisioned resource",
                                                                workspaceName => $workspace,
                                                                port          => $self->opts->{ec_vmport},
                                                                hostName      => $ipaddr,
                                                                pools         => $pool
                                                             }
                                                            );

            # Check for error return
            my $errMsg = $self->myCmdr()->checkAllErrors($cmdrresult);
            if ($errMsg ne "") {
                $self->debugMsg(1, "Error: $errMsg");
                $self->opts->{exitcode} = 1;
                $failedMachines{ $machine->{"name"} } = 1;
                next;
            }

            #-------------------------------------
            # Record the resource name created
            #-------------------------------------
            $setResult = $self->setProp("/resources/" . $propertyName . "/resName", $machineName);

            #-------------------------------------
            # Add the resource name to InstanceList
            #-------------------------------------
            if ("$instlist" ne "") { $instlist .= ";"; }
            $instlist .= "$propertyName";
            $self->debugMsg(1, "Adding $propertyName to instance list");

            #-------------------------------------
            # Wait for resource to respong to ping
            #-------------------------------------
            # If creation of resource failed, do not ping
            if (!defined($failedMachines{ $machine->{"name"} })
                || $failedMachines{ $machine->{"name"} == 0 })
            {

                my $resStarted = 0;

                # wait for machine to start
                my $try = $self->opts->{PingTimeout};
                while ($try > 0) {
                    $self->debugMsg(1, "Waiting for agent to start #(" . $try . ") for resource " . $machineName);
                    my $pingresult = $self->pingResource($machineName);
                    if ($pingresult == ALIVE) {
                        $resStarted = 1;
                        last;
                    }
                    sleep(1);
                    $try -= 1;
                }
                if ($resStarted == 0) {
                    $self->debugMsg(1, "Agent did not start");
                    $self->opts->{exitcode} = ERROR;
                }
            }
        }

        #-------------------------------------
        # Record the attributes of machines even
        # if we did not create a resource
        #-------------------------------------
        $setResult = $self->setProp("/resources/" . $propertyName . "/hostName", $ipaddr);

        ## Also record the other machine parameters
        ## eventually we should depracate "hostName"
        $setResult = $self->setProp("/resources/" . $propertyName . "/internalIP",  $machine->{"internalIP"});
        $setResult = $self->setProp("/resources/" . $propertyName . "/externalIP",  $machine->{"externalIP"});
        $setResult = $self->setProp("/resources/" . $propertyName . "/machineName", $machine->{"name"});
        $setResult = $self->setProp("/resources/" . $propertyName . "/machineID",   $machine->{"id"});
        $setResult = $self->setProp("/resources/" . $propertyName . "/description", $machine->{"description"});
        $setResult = $self->setProp("/resources/" . $propertyName . "/Workspace",   $self->opts->{labmanager_work});
        $setResult = $self->setProp("/resources/" . $propertyName . "/Org",         $self->opts->{labmanager_org});

    }

    if($instlist)
    {
    $self->debugMsg(1, "Saving vm list " . $instlist);
    $self->setProp("/VMList", $instlist);

    }
}

###############################
# cleanup - Cleanup a configuration using VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub cleanup {
    my ($self) = @_;
    
    $self->debugMsg(1, '---------------------------------------------------------------------');
    
    $self->opts->{LMUseInternalAPI} = TRUE;    # Internal API is used in some calls
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    if (($self->checkOption("PropPrefix", "required noblank") && $self->checkOption("labmanager_config", "required noblank"))
        || $self->checkOption("Tag", "required noblank"))
    {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my %result;
    my $deployedCfg = "";
    my $cfgName     = "";
    my @resources;

    if (!defined($self->opts->{labmanager_config})
        || ($self->opts->{labmanager_config} eq ""))
    {

        #-------------------------------------
        # Get cfg info from properties
        #-------------------------------------
        $deployedCfg = $self->getProp("/cfgId")   || "";
        $cfgName     = $self->getProp("/cfgName") || "";

        if ("$deployedCfg" eq "") {
            $self->debugMsg(0, "Could not find a cfgId in " . $self->opts->{PropPrefix} . "/cfgId");
            $self->opts->{exitcode} = ERROR;
            return;
        }

        $self->debugMsg(1, "Deployed cfgid=$deployedCfg");

        @resources = $self->getDeployedResourceListFromProperty();

    }
    else {

        #-------------------------------------
        # Get cfg info
        #-------------------------------------
        $self->debugMsg(5, "---------------------------------------------");
        %result = $self->CallLabManager("GetConfigurationByName", ("name" => $self->opts->{labmanager_config},));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: fetching Configuration Id ");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->setProp("/cleanup_error", $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return;
        }

        $deployedCfg = $result{"value"}[0]->{"id"};
        $cfgName     = $self->opts->{labmanager_config};

        if (!defined($deployedCfg) || ($deployedCfg eq "")) {
            $self->debugMsg(0, "Could not find a Configuration with name " . $self->opts->{labmanager_config});
            $self->opts->{exitcode} = ERROR;
            return;
        }

        $self->debugMsg(1, "Deployed cfgid=$deployedCfg");

        @resources = $self->getDeployedResourceList($deployedCfg, $cfgName);

    }

    #-------------------------------------
    # Delete resources (if created)
    #-------------------------------------
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, "Cleaning up resources");
    foreach my $machineName (@resources) {
        $self->debugMsg(1, "Deleting resource " . $machineName);
        my $cmdrresult = $self->myCmdr()->deleteResource($machineName);

        # Check for error return
        my $errMsg = $self->myCmdr()->checkAllErrors($cmdrresult);
        if ($errMsg ne "") {
            $self->debugMsg(1, "Error: $errMsg");
            $self->opts->{exitcode} = ERROR;
            next;
        }
    }

    #-------------------------------------
    # Get configuration to verify if it is already undeployed
    #-------------------------------------
    $self->debugMsg(5, "---------------------------------------------");
    %result = $self->CallLabManager("GetConfiguration", ("id" => $deployedCfg));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: getting LabManager configuration " . $deployedCfg);
        $self->debugMsg(0, "    " . $result{"faultstring"});
        
        $self->opts->{exitcode} = ERROR;
        
        return;
    }

    my @configurations        = @{ $result{"value"} };
    my $conf                  = $configurations[0];
    my $configurationDeployed = $conf->{"isDeployed"};

    # Shutdown machines and configuration ONLY if configuration is deployed
    if ($configurationDeployed eq LM_TRUE) {

        $self->shutdownConfiguration($deployedCfg);
        if ($self->ecode) { return; }
    }

    #-------------------------------------
    # Clone configuration if requested
    #-------------------------------------
    if (defined($self->opts->{save_configuration_name})
        && $self->opts->{save_configuration_name} ne "")
    {
        $self->cloneConfiguration($deployedCfg);
    }

    #-------------------------------------
    # Capture configuration to library if requested
    #-------------------------------------
    if (defined($self->opts->{new_library_name})
        && $self->opts->{new_library_name} ne "")
    {
        $self->captureConfiguration;
    }

    #-------------------------------------
    # Undeploy and remove configuration
    #-------------------------------------
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, "Cleaning up configuration " . $deployedCfg);

    # Undeploy configuration ONLY if configuration is deployed
    if ($configurationDeployed eq LM_TRUE) {
        $self->undeployConfiguration($deployedCfg, $cfgName);
        if ($self->ecode) { return; }
    }

    $self->deleteConfiguration($deployedCfg, $cfgName);
    if ($self->ecode) { return; }
$self->debugMsg(0, "---------------------------------------------");
    $self->debugMsg(0, "Cleanup finished");
}

###############################
# shutdownConfiguration - Call Lab Manager SOAP API to shut down a configuration
#
# Arguments:
#   cfgId   - configuration ID
#
# Returns:
#   none
#
###############################
sub shutdownConfiguration {
    my ($self, $cfgId) = @_;

    my %result;

    #-------------------------------------
    # Shutdown machines in configuration
    #-------------------------------------
    %result = $self->CallLabManager("ListMachines", ("configurationId" => $cfgId,));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: " . $result{"faultcode"} . " " . $result{"faultstring"} . " " . $result{"faultdetail"});
        $self->opts->{exitcode} = $result{"faultcode"};
        return;
    }

    my @machines = @{ $result{"value"} };

    # Shutdown machines
    foreach my $machine (@machines) {
        $self->debugMsg(1, "Shutting down:" . $machine->{"name"});
        %result = $self->CallLabManager(
                                        "MachinePerformAction",
                                        (
                                         "machineId" => $machine->{"id"},
                                         "action"    => ACTION_SHUTDOWN
                                        )
                                       );
        $self->debugMsg(1, "Shut down result:" . $result{"faultcode"} . " " . $result{"faultstring"});
    }

    # Wait for all machines to shut down
    foreach my $machine (@machines) {
        my $attempts = 20;
        while ($attempts > 0) {
            $attempts--;
            %result = $self->CallLabManager("GetMachine", ("machineId" => $machine->{"id"}));
            my @confMachines = @{ $result{"value"} };
            my $confMachine  = $confMachines[0];
            if ($confMachine->{"status"} == OFF) {
                last;
            }
            else {
                %result = $self->CallLabManager(
                                                "MachinePerformAction",
                                                (
                                                 "machineId" => $machine->{"id"},
                                                 "action"    => ACTION_SHUTDOWN
                                                )
                                               );
            }
            sleep(DEFAULT_SLEEP);
        }

        # Force-undeploy virtual machine
        $self->debugMsg(1, "Force-undeploying:" . $machine->{"name"});
        %result = $self->CallLabManager(
                                        "MachinePerformAction",
                                        (
                                         "machineId" => $machine->{"id"},
                                         "action"    => ACTION_FORCE_UNDEPLOY
                                        )
                                       );
        if ($result{"faultcode"}) {
            $self->debugMsg(1, "Unable to force-undeploy machine");
        }
    }

    #-------------------------------------
    # Shutdown configuration
    #-------------------------------------
    $self->debugMsg(1, "Shutting down configuration");
    %result = $self->CallLabManager(
                                    "ConfigurationPerformAction",
                                    (
                                     "configurationId" => $cfgId,
                                     "action"          => ACTION_OFF
                                    )
                                   );

    $self->debugMsg(1, "Shut down result:" . $result{"faultcode"} . " " . $result{"faultstring"});
}

###############################
# undeployConfiguration - Call Lab Manager SOAP API to undeploy a configuration
#
# Arguments:
#   cfgId   - configuration ID
#   cfgName - configuration name
#
# Returns:
#   none
#
###############################
sub undeployConfiguration {
    my ($self, $cfgId, $cfgName) = @_;

    my %result;

    # Undeploy configuration
    $self->debugMsg(1, "Undeploying configuration " . $cfgName);
    %result = $self->CallLabManager("ConfigurationUndeploy", ("configurationId" => $cfgId));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error undeploying configuration:");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }
}

###############################
# deleteConfiguration - Call Lab Manager SOAP API to delete a configuration
#
# Arguments:
#   cfgId   - configuration ID
#   cfgName - configuration name
#
# Returns:
#   none
#
###############################
sub deleteConfiguration {
    my ($self, $cfgId, $cfgName) = @_;

    my %result;

    # Delete configuration
    $self->debugMsg(1, "Deleting configuration " . $cfgName);
    %result = $self->CallLabManager("ConfigurationDelete", ("configurationId" => $cfgId));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error deleting configuration:");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }
}

###############################
# clone - Initialize and call cloneConfiguration
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub clone {
    my ($self) = @_;

    $self->opts->{LMUseInternalAPI} = TRUE;
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    # Get configuration ID
    my $cfgId = $self->getConfigurationID($self->opts->{labmanager_config});
    if ($self->opts->{exitcode}) { return; }

    # Call procedure to clone the configuration
    $self->cloneConfiguration($cfgId);
    if ($self->opts->{exitcode}) { return; }

    $self->debugMsg(0, "Configuration successfully cloned");
}

###############################
# cloneConfiguration - Clone a workspace configuration and set the owner of the configuration
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub cloneConfiguration {
    my ($self, $cfgId) = @_;

    my %result;

    # Clone configuration
    $self->debugMsg(1, "Cloning configuration to " . $self->opts->{save_configuration_name});
    %result = $self->CallLabManager(
                                    "ConfigurationClone",
                                    (
                                     "configurationId"  => $cfgId,
                                     "newWorkspaceName" => $self->opts->{save_configuration_name}
                                    )
                                   );

    my $cloneCfg = $result{"value"};

    if ($result{"faultcode"} or $cloneCfg <= 0) {
        $self->debugMsg(0, "Error: Clone configuration failed. Cleanup aborted");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    # Save configuration ID in properties
    my $setResult = $self->setProp("/savCfgId", $cloneCfg);

    # If user wants to set the owner of the configuration
    if (defined($self->opts->{save_configuration_owner})
        && $self->opts->{save_configuration_owner} ne "")
    {

        # Get User ID
        $self->debugMsg(2, "---------------------------------------------");
        $self->debugMsg(2, "Getting user with username '" . $self->opts->{save_configuration_owner} . "'");
        %result = $self->CallLabManager("GetUser", ("userName" => $self->opts->{save_configuration_owner}));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: getting user with username " . $self->opts->{save_configuration_owner});
            $self->debugMsg(0, "    " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return;
        }

        my @users  = @{ $result{"value"} };
        my $user   = $users[0];
        my $userID = $user->{"userId"};

        # Change configuration owner
        $self->debugMsg(1, "Setting owner of configuration '" . $self->opts->{save_configuration_name} . "' to user '" . $self->opts->{save_configuration_owner} . "'");
        %result = $self->CallLabManager(
                                        "ConfigurationChangeOwner",
                                        (
                                         "configurationId" => $cloneCfg,
                                         "newOwnerId"      => $userID
                                        )
                                       );

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error changing configuration owner:");
            $self->debugMsg(0, "    " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
        }
    }
}

###############################
# snapshot - Create a snapshot of a configuration or replace the existing one using VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub snapshot {

    my ($self) = @_;

    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    if (   $self->checkOption("PropPrefix", "required noblank")
        || $self->checkOption("Tag", "required noblank"))
    {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my %result;
    my $deployedCfg = "";
    my $cfgName     = "";
    if (!defined($self->opts->{labmanager_config}) || ($self->opts->{labmanager_config} eq "")) {

        #-------------------------------------
        # Get cfg info from properties
        #-------------------------------------
        $deployedCfg = $self->getProp("/cfgId") || "";

        if ($deployedCfg eq "") {
            $self->debugMsg(0, "Could not find a cfgId in " . $self->opts->{PropPrefix} . "/cfgId");
            $self->opts->{exitcode} = ERROR;
            return;
        }
        $self->debugMsg(1, "Deployed cfgid=$deployedCfg");
    }
    else {

        #-------------------------------------
        # Get cfg info
        #-------------------------------------
        %result = $self->CallLabManager("GetConfigurationByName", ("name" => $self->opts->{labmanager_config},));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: fetching Configuration Id ");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return;
        }

        $deployedCfg = $result{"value"}[0]->{"id"};

        if (!defined($deployedCfg) || ($deployedCfg eq "")) {
            $self->debugMsg(0, "Could not find a Configuration with name " . $self->opts->{labmanager_config});
            $self->opts->{exitcode} = ERROR;
            return;
        }

    }

    #-------------------------------------
    # Snapshot configuration
    #-------------------------------------
    $self->debugMsg(1, "Creating snapshot of configuration");
    %result = $self->CallLabManager(
                                    "ConfigurationPerformAction",
                                    (
                                     "configurationId" => $deployedCfg,
                                     "action"          => ACTION_SNAPSHOT
                                    )
                                   );
$self->debugMsg(0, "---------------------------------------------");
    $self->debugMsg(0, "Snapshot finished");
}

###############################
# revert - Revert the configuration to the last snapshot using VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub revert {

    my ($self) = @_;

    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    if (   $self->checkOption("PropPrefix", "required noblank")
        || $self->checkOption("Tag", "required noblank"))
    {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my %result;
    my $deployedCfg = "";
    my $cfgName     = "";
    if (!defined($self->opts->{labmanager_config}) || ($self->opts->{labmanager_config} eq "")) {

        #-------------------------------------
        # Get cfg info from properties
        #-------------------------------------
        $deployedCfg = $self->getProp("/cfgId") || "";

        if ($deployedCfg eq "") {
            $self->debugMsg(0, "Could not find a cfgId in " . $self->opts->{PropPrefix} . "/cfgId");
            $self->opts->{exitcode} = ERROR;
            return;
        }
        $self->debugMsg(1, "Deployed cfgid=$deployedCfg");
    }
    else {

        #-------------------------------------
        # Get cfg info
        #-------------------------------------
        %result = $self->CallLabManager("GetConfigurationByName", ("name" => $self->opts->{labmanager_config},));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: fetching Configuration Id ");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return;
        }

        $deployedCfg = $result{"value"}[0]->{"id"};

        if (!defined($deployedCfg) || ($deployedCfg eq "")) {
            $self->debugMsg(0, "Could not find a Configuration with name " . $self->opts->{labmanager_config});
            $self->opts->{exitcode} = ERROR;
            return;
        }

    }

    #-------------------------------------
    # Revert configuration
    #-------------------------------------
    $self->debugMsg(1, "Reverting configuration");
    %result = $self->CallLabManager(
                                    "ConfigurationPerformAction",
                                    (
                                     "configurationId" => $deployedCfg,
                                     "action"          => ACTION_REVERT
                                    )
                                   );
$self->debugMsg(0, "---------------------------------------------");
    $self->debugMsg(0, "Revert finished");

    return;
}

###############################
# capture - Initialize and call captureConfiguration to capture configuration to library
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub capture {

    my ($self) = @_;

    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    $self->captureConfiguration;
    if ($self->opts->{exitcode}) { return; }
$self->debugMsg(0, "---------------------------------------------");
    $self->debugMsg(0, "Capture finished");
}

###############################
# captureConfiguration - Capture a configuration and save it in LabManager library using VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub captureConfiguration {

    my ($self) = @_;

    $self->initializeDestinationPropPrefix;
    if ($self->opts->{exitcode}) { return; }

    # check required and non-blank values
    if (   $self->checkOption("PropPrefix", "required noblank")
        || $self->checkOption("Tag",                   "required noblank")
        || $self->checkOption("DestinationPropPrefix", "required noblank")
        || $self->checkOption("destination_tag",       "required noblank"))
    {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my %result;
    my $deployedCfg = "";
    my $cfgName     = "";
    if (!defined($self->opts->{labmanager_config}) || ($self->opts->{labmanager_config} eq "")) {

        #-------------------------------------
        # Get cfg info from properties
        #-------------------------------------
        $deployedCfg = $self->getProp("/cfgId")   || "";
        $cfgName     = $self->getProp("/cfgName") || "";

        if ($deployedCfg eq "") {
            $self->debugMsg(0, "Could not find a cfgId in " . $self->opts->{PropPrefix} . "/cfgId");
            $self->opts->{exitcode} = ERROR;
            return;
        }
    }
    else {

        #-------------------------------------
        # Get cfg info
        #-------------------------------------
        %result = $self->CallLabManager("GetConfigurationByName", ("name" => $self->opts->{labmanager_config},));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error: fetching Configuration Id ");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            return;
        }

        $deployedCfg = $result{"value"}[0]->{"id"};
        $cfgName     = $self->opts->{labmanager_config};

        if (!defined($deployedCfg) || ($deployedCfg eq "")) {
            $self->debugMsg(0, "Could not find a Configuration with name " . $self->opts->{labmanager_config});
            $self->opts->{exitcode} = ERROR;
            return;
        }

    }

    ############################################################################

    #-------------------------------------
    # Get configuration to verify if it is already undeployed
    #-------------------------------------
    %result = $self->CallLabManager("GetConfiguration", ("id" => $deployedCfg));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: getting LabManager configuration " . $deployedCfg);
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my @configurations        = @{ $result{"value"} };
    my $conf                  = $configurations[0];
    my $configurationDeployed = $conf->{"isDeployed"};

    # Shutdown machines and configuration ONLY if configuration is deployed
    if ($configurationDeployed eq LM_TRUE) {

        $self->undeployConfiguration($deployedCfg, $cfgName);
        if ($self->ecode) { return; }
    }

    ############################################################################

    #-------------------------------------
    # Capture configuration
    #-------------------------------------
    $self->debugMsg(1, "Capturing configuration with ID '$deployedCfg' and saving it to library");
    %result = $self->CallLabManager(
                                    "ConfigurationCapture",
                                    (
                                     "configurationId" => $deployedCfg,
                                     "newLibraryName"  => $self->opts->{new_library_name}
                                    )
                                   );

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: capturing configuration " . $cfgName);
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my $configurationId = $result{"value"};
    $self->debugMsg(0, "The configuration ID of the new capture is '$configurationId'");

    #-------------------------------------
    # Record the configuration name and ID in Commander
    #-------------------------------------
    $self->opts->{PropPrefix} = $self->opts->{DestinationPropPrefix};
    $self->debugMsg(1, "Recording configuration name and ID in destination location: '" . $self->opts->{DestinationPropPrefix} . "'");
    my $setResult = $self->setProp("/cfgId", $configurationId);
    $setResult = $self->setProp("/cfgName", $self->opts->{new_library_name});

    #$self->debugMsg(0,"Capture finished");
}

###############################
# configurationChangeOwner - Changes the owner of the given configuration
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub configurationChangeOwner {

    my ($self) = @_;

    $self->opts->{LMUseInternalAPI} = TRUE;
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    my %result;

    #-------------------------------------
    # Change configuration owner
    #-------------------------------------
    $self->debugMsg(1, "Changing configuration owner");
    %result = $self->CallLabManager(
                                    "ConfigurationChangeOwner",
                                    (
                                     "configurationId" => $self->opts->{labmanager_configurationid},
                                     "newOwnerId"      => $self->opts->{labmanager_newownerid}
                                    )
                                   );

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error changing configuration owner:");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    $self->debugMsg(0, "Owner of configuration '" . $self->opts->{labmanager_configurationid} . "' changed to user with ID '" . $self->opts->{labmanager_newownerid} . "'");
}

###############################
# createConfigurationFromVMTemplate - Create a new configuration and one or more machines based on templates
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub createConfigurationFromVMTemplate {

    my ($self) = @_;

    $self->opts->{LMUseInternalAPI} = TRUE;    # Internal API is used in some calls
    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }
    $self->initializePropPrefix;
    if ($self->opts->{exitcode}) { return; }

    if (   $self->checkOption("PropPrefix", "required noblank")
        || $self->checkOption("Tag", "required noblank"))
    {
        $self->opts->{exitcode} = ERROR;
        return;
    }

    #-------------------------------------
    # Declare variables and get input parameters
    #-------------------------------------
    my %result;
    my $setResult;

    my @vmTemplates   = split(/;/, $self->opts->{labmanager_vmtemplates});
    my @vmNames       = split(/;/, $self->opts->{labmanager_vmnames});
    my @bootSequences = split(/;/, $self->opts->{labmanager_boot_seq});
    my @bootDelays    = split(/;/, $self->opts->{labmanager_boot_delay});

    my $indexAll          = 0;
    my @vmTemplatesIDsAll = ();
    my @vmTemplatesAll    = ();
    my @vmNamesAll        = ();
    my @bootSequencesAll  = ();
    my @bootDelaysAll     = ();

    #-------------------------------------
    # Loop through VM templates and set values
    #-------------------------------------
    my $vmTemplateID;
    my $vmTemplate;
    my $vmName;
    my $bootSequence;
    my $bootDelay;

    my $indexTemplates = -1;
    my $indexInside    = 0;
    foreach (@vmTemplates) {

        # Increment index
        $indexTemplates++;

        $vmTemplate = $self->trim($vmTemplates[$indexTemplates]);
        if (!defined($vmNames[$indexTemplates])
            || $vmNames[$indexTemplates] eq "")
        {
            $vmName = "LM-VM" . $indexTemplates;
        }
        else {
            $vmName = $self->trim($vmNames[$indexTemplates]);
        }
        if (!defined($bootSequences[$indexTemplates])
            || $bootSequences[$indexTemplates] eq "")
        {
            $bootSequence = 0;
        }
        else {
            $bootSequence = $self->trim($bootSequences[$indexTemplates]);
        }
        if (!defined($bootDelays[$indexTemplates])
            || $bootDelays[$indexTemplates] eq "")
        {
            $bootDelay = 0;
        }
        else {
            $bootDelay = $self->trim($bootDelays[$indexTemplates]);
        }

        #-------------------------------------
        # Verify that labmanager_boot_seq and labmanager_boot_delay values are integers
        #-------------------------------------
        if (!$self->isNumber($bootSequence)) {
            $self->debugMsg(0, "Error: Boot sequence parameter for template $vmTemplate must be an integer");
            $self->opts->{exitcode} = ERROR;
            next;
        }
        if (!$self->isNumber($bootDelay)) {
            $self->debugMsg(0, "Error: Boot delay parameter for template $vmTemplate must be an integer");
            $self->opts->{exitcode} = ERROR;
            next;
        }

        #-------------------------------------
        # Get template IDs
        #-------------------------------------
        $self->debugMsg(1, "---------------------------------------------");
        $self->debugMsg(1, 'Getting VM template ' . $vmTemplate);
        %result = $self->CallLabManager("GetTemplateByName", ("name" => $vmTemplate));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error getting VM template:");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            next;
        }

        # Verify the template ID is defined at least for the first template
        if (!defined($result{"value"}[0]->{"id"})) {
            $self->debugMsg(0, "Error: A VM template named " . $vmTemplate . " was not found");
            $self->opts->{exitcode} = ERROR;
            next;
        }

        # Loop through template IDs (there may be more than one VM template with the same name, there must be at least one)
        $indexInside = 0;
        foreach ($result{"value"}) {
            $vmTemplateID = $result{"value"}[$indexInside]->{"id"};

            $vmTemplatesIDsAll[$indexAll] = $vmTemplateID;
            $vmTemplatesAll[$indexAll]    = $vmTemplate;
            $vmNamesAll[$indexAll]        = $vmName;
            $bootSequencesAll[$indexAll]  = $bootSequence;
            $bootDelaysAll[$indexAll]     = $bootDelay;

            $indexInside++;
            $indexAll++;
        }
    }

    #-------------------------------------
    # Create new configuration
    #-------------------------------------
    $self->debugMsg(1, 'Creating new configuration ' . $self->opts->{labmanager_name});
    if (defined($self->opts->{labmanager_version})
        && $self->opts->{labmanager_version} eq "4")
    {

        # Verify that labmanager_storage_lease and labmanager_deployment_lease values are integers
        if (!$self->isNumber($self->opts->{labmanager_deployment_lease})) {
            $self->debugMsg(0, "Error: Deployment lease parameter must be an integer");
            $self->opts->{exitcode} = ERROR;
            return;
        }
        if (!$self->isNumber($self->opts->{labmanager_storage_lease})) {
            $self->debugMsg(0, "Error: Storage lease parameter must be an integer");
            $self->opts->{exitcode} = ERROR;
            return;
        }

        %result = $self->CallLabManager(
                                        "ConfigurationCreateEx2",
                                        (
                                         "name"                          => $self->opts->{labmanager_name},
                                         "desc"                          => $self->opts->{labmanager_description},
                                         "fencePolicy"                   => $self->opts->{labmanager_fence_policy},
                                         "deploymentLeaseInMilliseconds" => $self->opts->{labmanager_deployment_lease},
                                         "storageLeaseInMilliseconds"    => $self->opts->{labmanager_storage_lease}
                                        )
                                       );
    }
    else {
        %result = $self->CallLabManager(
                                        "ConfigurationCreateEx",
                                        (
                                         "name" => $self->opts->{labmanager_name},
                                         "desc" => $self->opts->{labmanager_description}
                                        )
                                       );
    }

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error creating new configuration:");
        $self->debugMsg(0, "       " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }
    my $cfgId = $result{"value"};

    #-------------------------------------
    # Record the configuration info in properties
    #-------------------------------------
    $self->debugMsg(1, "Recording configuration information in properties: ID=$cfgId");
    $setResult = $self->setProp("/cfgId", $cfgId);
    if ($setResult eq "") {
        $self->debugMsg(0, "Error recording configuration ID:");
        $self->debugMsg(0, "       " . $setResult);
        %result = $self->CallLabManager("ConfigurationDelete", ("configurationId" => $cfgId));
        $self->opts->{exitcode} = ERROR;
        return;
    }
    $setResult = $self->setProp("/cfgName", $self->opts->{labmanager_name});

    #-------------------------------------
    # Add machines to the created configuration
    #-------------------------------------
    $indexAll = -1;
    foreach (@vmTemplatesIDsAll) {

        $indexAll++;

        # Get network information for the VM template
        $self->debugMsg(1, "---------------------------------------------");
        $self->debugMsg(1, 'Getting network information for VM template with ID ' . $vmTemplatesIDsAll[$indexAll]);
        %result = $self->CallLabManager("GetNetworkInfo", ("vmID" => $vmTemplatesIDsAll[$indexAll],));

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error getting network information:");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            next;
        }

        # Create array of network information
        my @netInfo = ();
        $indexInside = 0;
        foreach ($result{"value"}) {
            my %networkHash = ();
            $networkHash{"networkId"} = $result{"value"}[$indexInside]->{"networkId"}
            if (defined($result{"value"}[$indexInside]->{"networkId"})
                && $result{"value"}[$indexInside]->{"networkId"} ne "");
            $networkHash{"nicId"} = $result{"value"}[$indexInside]->{"nicId"}
            if (defined($result{"value"}[$indexInside]->{"nicId"})
                && $result{"value"}[$indexInside]->{"nicId"} ne "");
            $networkHash{"vmxSlot"} = $result{"value"}[$indexInside]->{"vmxSlot"}
            if (defined($result{"value"}[$indexInside]->{"vmxSlot"})
                && $result{"value"}[$indexInside]->{"vmxSlot"} ne "");
            $networkHash{"macAddress"} = $result{"value"}[$indexInside]->{"macAddress"}
            if (defined($result{"value"}[$indexInside]->{"macAddress"})
                && $result{"value"}[$indexInside]->{"macAddress"} ne "");
            $networkHash{"resetMac"} = $result{"value"}[$indexInside]->{"resetMac"}
            if (defined($result{"value"}[$indexInside]->{"resetMac"})
                && $result{"value"}[$indexInside]->{"resetMac"} ne "");
            $networkHash{"ipAddressingMode"} = $result{"value"}[$indexInside]->{"ipAddressingMode"}
            if (defined($result{"value"}[$indexInside]->{"ipAddressingMode"})
                && $result{"value"}[$indexInside]->{"ipAddressingMode"} ne "");
            $networkHash{"ipAddress"} = $result{"value"}[$indexInside]->{"ipAddress"}
            if (defined($result{"value"}[$indexInside]->{"ipAddress"})
                && $result{"value"}[$indexInside]->{"ipAddress"} ne "");
            $networkHash{"externalIpAddress"} = $result{"value"}[$indexInside]->{"externalIpAddress"}
            if (defined($result{"value"}[$indexInside]->{"externalIpAddress"})
                && $result{"value"}[$indexInside]->{"externalIpAddress"} ne "");
            $networkHash{"netmask"} = $result{"value"}[$indexInside]->{"netmask"}
            if (defined($result{"value"}[$indexInside]->{"netmask"})
                && $result{"value"}[$indexInside]->{"netmask"} ne "");
            $networkHash{"gateway"} = $result{"value"}[$indexInside]->{"gateway"}
            if (defined($result{"value"}[$indexInside]->{"gateway"})
                && $result{"value"}[$indexInside]->{"gateway"} ne "");
            $networkHash{"dns1"} = $result{"value"}[$indexInside]->{"dns1"}
            if (defined($result{"value"}[$indexInside]->{"dns1"})
                && $result{"value"}[$indexInside]->{"dns1"} ne "");
            $networkHash{"dns2"} = $result{"value"}[$indexInside]->{"dns2"}
            if (defined($result{"value"}[$indexInside]->{"dns2"})
                && $result{"value"}[$indexInside]->{"dns2"} ne "");
            $networkHash{"isConnected"} = $result{"value"}[$indexInside]->{"isConnected"}
            if (defined($result{"value"}[$indexInside]->{"isConnected"})
                && $result{"value"}[$indexInside]->{"isConnected"} ne "");

            push(@netInfo, { "NetInfo" => {%networkHash} });
            $indexInside++;
        }

        $self->debugMsg(1, 'Adding virtual machine ' . $vmNamesAll[$indexAll] . ' based on template with ID ' . $vmTemplatesIDsAll[$indexAll] . ' to configuration ' . $self->opts->{labmanager_name});
        %result = $self->CallLabManager(
                                        "ConfigurationAddMachineEx",
                                        (
                                         "id"          => $cfgId,
                                         "template_id" => $vmTemplatesIDsAll[$indexAll],
                                         "name"        => $vmNamesAll[$indexAll],
                                         "desc"        => "LabManager virtual machine",
                                         "boot_seq"    => $bootSequencesAll[$indexAll],
                                         "boot_delay"  => $bootDelaysAll[$indexAll],
                                         "netInfo"     => \@netInfo,
                                        )
                                       );

        if ($result{"faultcode"}) {
            $self->debugMsg(0, "Error adding virtual machine to configuration:");
            $self->debugMsg(0, "       " . $result{"faultstring"});
            $self->opts->{exitcode} = ERROR;
            next;
        }
    }

    #-------------------------------------
    # Set configuration state to public or private
    #-------------------------------------
    $self->setState($cfgId);

    #-------------------------------------
    # Deploy the configuration
    #-------------------------------------
    my $res = $self->deployConfiguration($cfgId, $self->opts->{labmanager_name});
    if ($res eq ERROR) { return; }

    #-------------------------------------
    # Create resources and save information in properties
    #-------------------------------------
    $self->createResources($cfgId, $self->opts->{labmanager_name});

    $self->debugMsg(0, "Successfully created new configuration with ID " . $cfgId . " and added virtual machine(s)");
}

###############################
# bulkCleanup - Clenaup multiple configurations using VMWare LabManager API
#
# Arguments:
#   none
#
# Returns:
#   none
#
###############################
sub bulkCleanup {
    my ($self) = @_;

    $self->Initialize();
    if ($self->opts->{exitcode}) { return; }

    my %result;

    if ($self->opts->{labmanager_days_old} ne ""
        && !$self->isNumber($self->opts->{labmanager_days_old}))
    {
        $self->debugMsg(0, "Error: Days old parameter must be an integer");
        $self->opts->{exitcode} = ERROR;
        return;
    }

    #-------------------------------------
    # Get Configurations
    #-------------------------------------
    $self->debugMsg(1, "---------------------------------------------");
    $self->debugMsg(1, "Getting configurations");
    %result = $self->CallLabManager("ListConfigurations", ("configurationType" => WORKSPACECONFIGS));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error listing configurations:");
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    # Get local time
    my $currentDate = DateTime->now();

    #-------------------------------------
    # Undeploy and delete configurations
    #-------------------------------------
    foreach my $node (@{ $result{"value"} }) {

        my $pattern = $self->opts->{labmanager_name_pattern};

        # Verify owner and pattern
        if (   $node->{"owner"} eq $self->opts->{labmanager_user}
            && $node->{"name"} =~ m/$pattern/)
        {

            # Verify configuration is older than value in labmanager_days_old
            if ($self->opts->{labmanager_days_old} ne "") {

                $node->{"dateCreated"} =~ /([0-9]{4})-([0-9]{2})-([0-9]{2}).*/;
                my $date     = DateTime->new(year => $1, month => $2, day => $3);
                my $duration = $currentDate->delta_days($date);
                my $daysOld  = $duration->in_units('days');

                # If configuration is newer than labmanager_days_old, skip it
                if ($daysOld < $self->opts->{labmanager_days_old}) {
                    next;
                }
            }

            $self->debugMsg(1, "Cleaning up configuration " . $node->{"name"} . ":");

            if ($node->{"isDeployed"} eq LM_TRUE) {

                # Undeploy configuration
                $self->shutdownConfiguration($node->{"id"});
                if ($self->ecode) { next; }

                $self->undeployConfiguration($node->{"id"}, $node->{"name"});
                if ($self->ecode) { next; }
            }

            if ($self->opts->{labmanager_delete}) {

                # Delete configuration
                $self->deleteConfiguration($node->{"id"}, $node->{"name"});
                if ($self->ecode) { next; }
            }
        }
    }

    $self->debugMsg(0, "---------------------------------------------");
    $self->debugMsg(0, "Bulk cleanup finished");
}

###############################
# getConfigurationID - Get a configuration ID given a configuration name
#
# Arguments:
#   cfgName - name of the configuration
#
# Returns:
#    ID of the configuration
#
###############################
sub getConfigurationID {
    my ($self, $cfgName) = @_;

    my %result;

    #-------------------------------------
    # Get configuration
    #-------------------------------------
    %result = $self->CallLabManager("GetConfigurationByName", ("name" => $cfgName));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: getting LabManager configuration " . $cfgName);
        $self->debugMsg(0, "    " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my $cfgId = $result{"value"}[0]->{"id"};

    # Verify that configuration existed
    if (!defined($cfgId)) {
        $self->debugMsg(0, "Error: A configuration named " . $cfgName . " was not found");
        $self->opts->{exitcode} = ERROR;
        return;
    }

    return $cfgId;
}

###############################
# pingResource - Use commander to ping a resource
#
# Arguments:
#   resource - string
#
# Returns:
#   1 if alive, 0 otherwise
#
###############################
sub pingResource {
    my ($self, $resource) = @_;

    my $alive  = "0";
    my $result = $self->myCmdr()->pingResource($resource);
    if (!$result) { return NOT_ALIVE; }
    $alive = $result->findvalue('//alive');
    if ($alive eq ALIVE) { return ALIVE; }
    return NOT_ALIVE;
}

###############################
# getDeployedResourceListFromProperty - Read the list of configurations deployed for a tag
#
# Arguments:
#   none
#
# Returns:
#   array of resources on success
#   empty array on failure
#
###############################
sub getDeployedResourceListFromProperty {
    my ($self) = @_;
    my @resources = ();

    my $propPrefix = $self->opts->{PropPrefix};

    $self->debugMsg(2, "Finding resources recorded in path " . $propPrefix);

    my $xPath = $self->myCmdr()->getProperties(
                                               {
                                                 path      => $propPrefix,
                                                 "recurse" => "1"
                                               }
                                              );

    my $nodeset = $xPath->find('//property[propertyName="resources"]/propertySheet/property');

    foreach my $node ($nodeset->get_nodelist) {
        my $propertyName = $xPath->findvalue('propertyName', $node);
        my $resName = $xPath->findvalue('//property[propertyName="' . $propertyName . '"]/propertySheet/property[propertyName="resName"]/value', $node);
        if ($resName ne "") {
            $self->debugMsg(1, "Found deployed resource " . $resName);
            push @resources, $resName;
        }
    }
    return @resources;
}

###############################
# getDeployedResourceList - Read the list of configurations deployed
#
# Arguments:
#   none
#
# Returns:
#   array of resources on success
#   empty array on failure
#
###############################
sub getDeployedResourceList {
    my ($self, $cfg, $cfgName) = @_;
    my @resources = ();

    my %result;

    %result = $self->CallLabManager("ListMachines", ("configurationId" => $cfg));

    if ($result{"faultcode"}) {
        $self->debugMsg(0, "Error: fetching List of machines");
        $self->debugMsg(0, "       " . $result{"faultstring"});
        $self->opts->{exitcode} = ERROR;
        return;
    }

    my @machines = @{ $result{"value"} };

    $self->debugMsg(2, "Finding resources for cfg " . $cfgName);

    # Get machines
    foreach my $machine (@machines) {
        my $resName = $cfgName . '_' . $machine->{"name"};
        if ($resName ne "") {
            $self->debugMsg(1, "Found deployed resource " . $resName);
            push @resources, $resName;
        }
    }

    return @resources;
}

#######################################################################
# LabManager SOAP Wrappers
#######################################################################

# -------------------------------------------------------------------------
# Table of commands and parameters
#
# cmd           - the command to run
# arg           - list of required arguments
# retFld        - the root of XML return to pass to valueof()
# retType
#    SCALAR     - a single value (string or numeric)
#    NONE       - this call does not return a value
#    RECORD     - this call returns one record
# retRec        - record structure (fields)
# requiresInternalAPI  - an optional Boolean that defines that
#                        the call is based on Internal API only
#
# -------------------------------------------------------------------------
%::gCommands = (
    "ConfigurationCapture" => {
                                cmd     => "ConfigurationCapture",
                                arg     => ["newLibraryName", "configurationId"],
                                retFld  => "ConfigurationCaptureResult",
                                retType => "SCALAR",
                                retRec  => ["newConfigurationId"],
                              },
    "ConfigurationCheckout" => {
                                 cmd     => "ConfigurationCheckout",
                                 arg     => ["workspaceName", "configurationId"],
                                 retFld  => "ConfigurationCheckoutResult",
                                 retType => "SCALAR",
                                 retRec  => ["workspaceId"],
                               },
    "ConfigurationClone" => {
                              cmd     => "ConfigurationClone",
                              arg     => ["newWorkspaceName", "configurationId"],
                              retFld  => "ConfigurationCloneResult",
                              retType => "SCALAR",
                              retRec  => ["newConfigurationId"],
                            },
    "ConfigurationDelete" => {
                               cmd     => "ConfigurationDelete",
                               arg     => ["configurationId"],
                               retFld  => "",
                               retType => "NONE",
                               retRec  => [],
                             },
    "ConfigurationDeploy" => {
                               cmd     => "ConfigurationDeploy",
                               arg     => ["configurationId", "isCached", "fenceMode"],
                               retFld  => "",
                               retType => "NONE",
                               retRec  => [],
                             },
    "ConfigurationPerformAction" => {
                                      cmd     => "ConfigurationcPerformAction",
                                      arg     => ["configurationId", "action"],
                                      retFld  => "",
                                      retType => "NONE",
                                      retRec  => [],
                                    },
    "ConfigurationSetPublicPrivate" => {
                                         cmd     => "ConfigurationSetPublicPrivate",
                                         arg     => ["configurationId", "isPublic"],
                                         retFld  => "",
                                         retType => "NONE",
                                         retRec  => [],
                                       },
    "ConfigurationUndeploy" => {
                                 cmd     => "ConfigurationcUndeploy",
                                 arg     => ["configurationId"],
                                 retFld  => "",
                                 retType => "NONE",
                                 retRec  => [],
                               },
    "GetConfiguration" => {
                            cmd     => "GetConfiguration",
                            arg     => ["id"],
                            retFld  => "GetConfigurationResult",
                            retType => "RECORD",
                            retRec  => ["id", "name", "description", "isPublic", "isDeployed", "fenceMode", "type", "owner", "dateCreated"],
                          },
    "GetConfigurationByName" => {
                                  cmd     => "GetConfigurationByName",
                                  arg     => ["name"],
                                  retFld  => "Configuration",
                                  retType => "RECORD",
                                  retRec  => ["id", "name", "description", "isPublic", "isDeployed", "fenceMode", "type", "owner", "dateCreated"],
                                },
    "GetMachine" => {
                      cmd     => "GetMachine",
                      arg     => ["machineId"],
                      retFld  => "GetMachineResult",
                      retType => "RECORD",
                      retRec  => ["id", "name", "description", "internalIP", "externalIP", "status", "isDeployed",],
                    },
    "GetMachineByName" => {
                            cmd     => "GetMachineByName",
                            arg     => ["configurationId", "name"],
                            retFld  => "GetMachineByNameResult",
                            retType => "RECORD",
                            retRec  => ["id", "name", "description", "internalIP", "externalIP", "status", "isDeployed",],
                          },
    "GetSingleConfigurationByName" => {
                                        cmd     => "GetSingleConfigurationByName",
                                        arg     => ["name"],
                                        retFld  => "GetSingleConfigurationByNameResult",
                                        retType => "RECORD",
                                        retRec  => ["id", "name", "description", "isPublic", "isDeployed", "fenceMode", "type", "owner", "dateCreated"],
                                      },
    "ListConfigurations" => {
                              cmd     => "ListConfigurations",
                              arg     => ["configurationType"],
                              retFld  => "Configuration",
                              retType => "RECORD",
                              retRec  => ["id", "name", "description", "isPublic", "isDeployed", "fenceMode", "type", "owner", "dateCreated"],
                            },
    "ListMachines" => {
                        cmd     => "ListMachines",
                        arg     => ["configurationId"],
                        retFld  => "Machine",
                        retType => "RECORD",
                        retRec  => ["id", "name", "description", "internalIP", "externalIP", "status", "isDeployed",],
                      },
    "LiveLink" => {
                    cmd     => "LiveLink",
                    arg     => ["configurationName"],
                    retFld  => "LiveLinkResult",
                    retType => "SCALAR",
                    retRec  => ["url"],
                  },
    "MachinePerformAction" => {
                                cmd     => "MachinePerformAction",
                                arg     => ["machineId", "action"],
                                retFld  => "",
                                retType => "NONE",
                                retRec  => [],
                              },
    "GetWorkspaceByName" => {
                              cmd     => "GetWorkspaceByName",
                              arg     => ["workspaceName"],
                              retFld  => "GetWorkspaceByNameResult",
                              retType => "RECORD",
                              retRec  => ["Configurations", "Id", "ResourcePools", "BucketType", "StoredVMQuota", "DeployedVMQuota", "Name", "Description", "IsEnabled"],
                            },

    ###############################################################
    #  Extended Commands from
    #      https://labmanager/LabManager/SOAP/LabManagerInternal.asmx
    ###############################################################

    "ConfigurationAddMachineEx" => {
                                     cmd                 => "ConfigurationAddMachineEx",
                                     arg                 => ["id", "template_id", "name", "desc", "boot_seq", "boot_delay", "netInfo",],
                                     retFld              => "ConfigurationAddMachineExResult",
                                     retType             => "SCALAR",
                                     retRec              => ["newMachineId"],
                                     requiresInternalAPI => "1",
                                   },
    "ConfigurationChangeOwner" => {
                                    cmd                 => "ConfigurationChangeOwner",
                                    arg                 => ["configurationId", "newOwnerId"],
                                    retFld              => "",
                                    retType             => "NONE",
                                    retRec              => [],
                                    requiresInternalAPI => "1",
                                  },
    "ConfigurationCloneToWorkspace" => {
                                         cmd                 => "ConfigurationCloneToWorkspace",
                                         arg                 => ["configID", "destWorkspaceId", "isNewConfiguration", "newConfigName", "description", "configurationCopyData", "existingConfigId", "isFullClone", "storageLeaseInMilliseconds"],
                                         retFld              => "ConfigurationCloneToWorkspaceResult",
                                         retType             => "SCALAR",
                                         retRec              => ["newConfigurationId"],
                                         requiresInternalAPI => "1",
                                       },
    "ConfigurationCreateEx" => {
                                 cmd                 => "ConfigurationCreateEx",
                                 arg                 => ["name", "desc",],
                                 retFld              => "ConfigurationCreateExResult",
                                 retType             => "SCALAR",
                                 retRec              => ["newConfigurationId"],
                                 requiresInternalAPI => "1",
                               },
    "ConfigurationCreateEx2" => {
                                  cmd                 => "ConfigurationCreateEx2",
                                  arg                 => ["name", "desc", "fencePolicy", "deploymentLeaseInMilliseconds", "storageLeaseInMilliseconds",],
                                  retFld              => "ConfigurationCreateEx2Result",
                                  retType             => "SCALAR",
                                  retRec              => ["newConfigurationId"],
                                  requiresInternalAPI => "1",
                                },

    # fenceNetworkOptions and bridgeNetworkOptions must be array references
    "ConfigurationDeployEx" => {
                                 cmd                 => "ConfigurationDeployEx",
                                 arg                 => ["configurationId", "honorBootOrder", "startAfterDeploy", "fenceNetworkOptions", "bridgeNetworkOptions"],
                                 retFld              => "",
                                 retType             => "NONE",
                                 retRec              => [],
                                 requiresInternalAPI => "1",
                               },

    # fenceNetworkOptions and bridgeNetworkOptions must be array references
    "ConfigurationDeployEx2" => {
                                  cmd                 => "ConfigurationDeployEx",
                                  arg                 => ["configurationId", "honorBootOrder", "startAfterDeploy", "fenceNetworkOptions", "bridgeNetworkOptions", "isCrossHost"],
                                  retFld              => "",
                                  retType             => "NONE",
                                  retRec              => [],
                                  requiresInternalAPI => "1",
                                },
    "ConfigurationGetNetworks" => {
                                    cmd                 => "ConfigurationGetNetworks",
                                    arg                 => ["configID", "physical"],
                                    retFld              => "ConfigurationGetNetworksResult/int",
                                    retType             => "RECORD",
                                    retRec              => ["int"],
                                    requiresInternalAPI => "1",
                                  },
    "GetDefaultPhysicalNetwork" => {
                                     cmd                 => "GetDefaultPhysicalNetwork",
                                     arg                 => [],
                                     retFld              => "GetDefaultPhysicalNetworkResult",
                                     retType             => "SCALAR",
                                     retRec              => ["defaultPhysicalNetwork"],
                                     requiresInternalAPI => "1",
                                   },
    "GetNetworkInfo" => {
                          cmd                 => "GetNetworkInfo",
                          arg                 => ["vmID"],
                          retFld              => "NetInfo",
                          retType             => "RECORD",
                          retRec              => ["networkId", "nicId", "vmxSlot", "macAddress", "resetMac", "ipAddressingMode", "ipAddress", "externalIpAddress", "netmask", "gateway", "dns1", "dns2", "isConnected",],
                          requiresInternalAPI => "1",
                        },
    "GetTemplateByName" => {
                             cmd                 => "GetTemplateByName",
                             arg                 => ["name"],
                             retFld              => "Template",
                             retType             => "RECORD",
                             retRec              => ["id", "name", "description", "storage_id", "virtualization_id", "memory", "mac_address", "isAutoConfigEnabled", "isPublic", "isPublished", "isBusy", "isDeployed", "status", "managedServerDeployed",],
                             requiresInternalAPI => "1",
                           },
    "GetUser" => {
                   cmd                 => "GetUser",
                   arg                 => ["userName"],
                   retFld              => "GetUserResult",
                   retType             => "RECORD",
                   retRec              => ["e", "full_name", "email_address", "stored_vm_quota", "deployed_vm_quota", "cache_mode", "fence_mode", "boot_delay", "use_boot_sequence", "is_enabled", "is_admin", "is_ldap", "userId",],
                   requiresInternalAPI => "1",
                 },
    "LibraryCloneToWorkspace" => {
                                   cmd                 => "LibraryCloneToWorkspace",
                                   arg                 => ["libraryId", "destWorkspaceId", "isNewConfiguration", "newConfigName", "description", "copyData", "existingConfigId", "isFullClone", "storageLeaseInMilliseconds"],
                                   retFld              => "LibraryCloneToWorkspaceResult",
                                   retType             => "SCALAR",
                                   retRec              => ["newConfigurationId"],
                                   requiresInternalAPI => "1",
                                 },

    "ListNetworks" => {
                        cmd                 => "ListNetworks",
                        arg                 => [],
                        retFld              => "Network",
                        retType             => "RECORD",
                        retRec              => ["DeployFenced", "DeployFencedMode", "Description", "Dns1", "Dns2", "DnsSuffix", "Gateway", "IPAddressingMode", "IsAddressingModeLocked", "IsDeployFencedLocked", "IsNone", "IsPhysical", "Name", "NetID", "Netmask", "NetType", "VlanID", "NetworkValref", "parentNetId", "userId"],
                        requiresInternalAPI => "1",
                      },
    "GetOrganizationWorkspaces" => {
                                     cmd                 => "GetOrganizationWorkspaces",
                                     arg                 => ["organizationId"],
                                     retFld              => "Workspace",
                                     retType             => "RECORD",
                                     retRec              => ["Configurations", "Id", "ResourcePools", "BucketType", "StoredVMQuota", "DeployedVMQuota", "Name", "Description", "IsEnabled"],
                                     requiresInternalAPI => "1",
                                   },
    "GetOrganizationByName" => {
                                 cmd                 => "GetOrganizationByName",
                                 arg                 => ["organizationName"],
                                 retFld              => "GetOrganizationByNameResult",
                                 retType             => "RECORD",
                                 retRec              => ["Id", "ResourcePools", "StoredVMQuota", "DeployedVMQuota", "Name", "Description", "IsEnabled"],
                                 requiresInternalAPI => "1",
                               },
    "GetCurrentOrganization" => {
                                  cmd                 => "GetCurrentOrganization",
                                  arg                 => [],
                                  retFld              => "GetCurrentOrganizationResult",
                                  retType             => "RECORD",
                                  retRec              => ["Id", "ResourcePools", "StoredVMQuota", "DeployedVMQuota", "Name", "Description", "IsEnabled"],
                                  requiresInternalAPI => "1",
                                },
               );

###############################
# CallLabManager - Read the list of configurations deployed for a tag
#
# Arguments:
#   cmd - string
#   args - array of args in name => value format
#
# Returns:
#   returns result based on requested function
#        %ret
#            value          value returned from SOAP call (scalar or array)
#            faultcode      error code (0 if no error)
#            faultstring    fault string from SOAP call
#            faultdetail    more fault detail from SOAP call
#            retType        SCALAR, NONE, RECORD
#            retFld         Name of node in return XML to parse
#            retRec         List of field names in returned record
#
###############################
sub CallLabManager {

    my ($self, $cmd, %argsin) = @_;

    my %ret = ();
    $ret{"value"}       = "";
    $ret{"faultcode"}   = 0;
    $ret{"faultstring"} = "";
    $ret{"faultdetail"} = "";
    
    
    $self->debugMsg(5, "=> CallLabManager: $cmd");

    # find command in global command table
    if (!$::gCommands{$cmd}) {
        $self->debugMsg(1, "Error: CallLabManager: unknown command $cmd");
        $ret{"faultcode"}   = -1;
        $ret{"faultstring"} = "$cmd: unknown command";
        return (%ret);
    }

    # Test for a command based on Internal API
    if ($::gCommands{$cmd}{"requiresInternalAPI"}) {
        if (   !defined($self->opts->{LMUseInternalAPI})
            || !$self->opts->{LMUseInternalAPI})
        {
            $self->debugMsg(1, "Error: CallLabManager: command $cmd requires the Internal API");
            $ret{"faultcode"}   = -1;
            $ret{"faultstring"} = "$cmd: API version error";
            return (%ret);
        }
    }

    my @cmdTableArgs = @{ $::gCommands{$cmd}{"arg"} };

    $ret{"retType"} = $::gCommands{$cmd}{"retType"};
    $ret{"retFld"}  = $::gCommands{$cmd}{"retFld"};
    $ret{"retRec"}  = $::gCommands{$cmd}{"retRec"};

    my @soapargs = ();

    # for each required arg
    foreach my $arg (@cmdTableArgs) {
        #$self->debugMsg(5, "=> CallLabmanager");

        # find the value in the list of args passed in
        if (!defined $argsin{$arg}) {
            $self->debugMsg(1, "Error: required arg $arg not found for $cmd");
            $ret{"faultcode"}   = -2;
            $ret{"faultstring"} = "missing required argument:$arg";
            return (%ret);
        }
        $self->debugMsg(5, "    -arg $arg=$argsin{$arg}");

        # lookup value passed in for this arg
        my $value = $argsin{$arg};

        # Check for an array reference
        if (ref($value) eq 'ARRAY') {

            $self->debugMsg(99, "       $arg is ARRAY");

            # Loop over all the outer elements
            my @outerSoapargs = ();
            foreach my $outerHashRef (@$value) {

                my $outerName = (keys %$outerHashRef)[0];
                $self->debugMsg(99, "       $outerName outer element");
                my $innerHashRef = $outerHashRef->{$outerName};

                # Loop over inner elements
                my @innerSoapargs = ();
                foreach my $innerName (keys %$innerHashRef) {
                    $self->debugMsg(99, "          $innerName - $innerHashRef->{$innerName}");
                    push @innerSoapargs, SOAP::Data->name($innerName => $innerHashRef->{$innerName});
                }

                push @outerSoapargs, SOAP::Data->name($outerName => \SOAP::Data->value(@innerSoapargs));
            }

            if (@outerSoapargs) {
                push @soapargs, SOAP::Data->name($arg => \SOAP::Data->value(@outerSoapargs));
            }

            # Finished with this arg
            next;
        }

        # make sure it is a string because something in the
        # perl LITE lib remembers that it was a struct
        # and creates wierd headers with <c-gensym4> tags unless
        # we pass in a string. My Perl is not good enough to know how
        # to cast this correctly, but this works.
        my $strarg = substr($arg,   0);
        my $strval = substr($value, 0);

        $self->debugMsg(5, "       pushing $strarg=$strval as SOAP::Data element");

        # push onto SOAP call parameters
        push @soapargs, SOAP::Data->name($strarg => $strval);
        $self->debugMsg(99, "       $arg=$value");
    }

    # call SOAP
    my $result = $self->SOAP_CALL($cmd, @soapargs);

    # on error from SOAP
    if($result eq SOAP_ERROR) {
        $ret{"faultcode"}   = SOAP_ERROR;
        $ret{"faultstring"} = "Test connection failed.";
        $ret{"faultdetail"} = "SOAP call failed.";
        return (%ret);
    } else {
        if ($result->fault) {
            $ret{"faultcode"}   = $result->faultcode;
            $ret{"faultstring"} = $result->faultstring;
            $ret{"faultdetail"} = $result->faultdetail;
            return (%ret);
        }
     }
    # parse result
    my $retFld = $ret{"retFld"};
    if ($ret{"retType"} eq "SCALAR") {
        my $tmpScalar = $result->valueof('//' . $retFld);
        $ret{"value"} = $tmpScalar;
        return (%ret);
    }

    if ($ret{"retType"} eq "RECORD") {
        my @retArray = $result->valueof('//' . $retFld);
        $ret{"value"} = [@retArray];
        return (%ret);
    }

    # otherwise nothing to return
    return (%ret);

}

###############################
# SOAP_CALL - Make SOAP call to LabManager
#
# Arguments:
#   Method name
#   Arguments
#
# Returns:
#   returns array of configurations
#
###############################
sub SOAP_CALL {

    my ($self, $methodName, @args) = @_;

    $self->debugMsg(5, "Creating SOAP::Lite objects");
    $self->debugMsg(5, "Proxy:" . $self->opts->{Proxy});
    $self->debugMsg(5, "Timeout:" . $self->opts->{SoapTimeout});
    # --------------------------------------------------
    # action must be set since LM SOAP server expects
    # .NET style SOAPAction $uri/method whereas
    # SOAP::Lite defaults to $uri#method
    # --------------------------------------------------
    my $soap = SOAP::Lite->proxy($self->opts->{Proxy}, timeout => $self->opts->{SoapTimeout})->autotype(0)->on_action(
        sub {
            sprintf('"http://vmware.com/labmanager/%s"', $methodName);
        }
    )->uri('http://vmware.com/labmanager');
    $self->debugMsg(5, "Setting auth headers");
    $self->debugMsg(5, "User:" . $self->opts->{labmanager_user});
    $self->debugMsg(5, "Pass:" . $self->opts->{labmanager_pass});
    $self->debugMsg(5, "Org:" . $self->opts->{labmanager_org});
    if (!defined($self->opts->{labmanager_work})) {
        $self->opts->{labmanager_work} = '';
    }
    $self->debugMsg(5, "Workspace:" . $self->opts->{labmanager_work});
    # -------------------------------------------------
    # LabManager SOAP Server expects authorization in
    # header (not basic auth)
    # -------------------------------------------------
    my $uri       = 'http://vmware.com/labmanager';
    my $user      = substr($self->opts->{labmanager_user}, 0);
    my $password  = substr($self->opts->{labmanager_pass}, 0);
    my $org       = substr($self->opts->{labmanager_org}, 0);
    my $workspace = substr($self->opts->{labmanager_work}, 0);

    my $AuthHeader = SOAP::Header->new(
                                       name  => 'AuthenticationHeader',
                                       attr  => { xmlns => 'http://vmware.com/labmanager' },
                                       value => {
                                                  username         => $user,
                                                  password         => $password,
                                                  organizationname => $org,
                                                  workspacename    => $workspace
                                                }
                                      );
    # -------------------------------------------------
    # Combine the authentication header and args
    # -------------------------------------------------
    my @params = ($AuthHeader, @args);
    # -------------------------------------------------
    # Prepare method name as SOAP::Data item
    # -------------------------------------------------    
    my $method = SOAP::Data->name($methodName)->attr({ xmlns => 'http://vmware.com/labmanager' });
    # -------------------------------------------------
    # Make the call
    # -------------------------------------------------    
    my $result;
    
    
    eval{$result = $soap->call($method => @params);};
    if($@){
        $result = SOAP_ERROR;        
    }
    # -------------------------------------------------
    # If we are debugging, show low level faults
    # -------------------------------------------------
    if ($self->opts->{debug} > 1) {
        if ($result->fault) {
            print join ', ', $result->faultcode, $result->faultstring, "\n";
        }
    }
    return $result;
}

###############################
# isNumber - Determine if a variable is a number or not
#
# Arguments:
#   var
#
# Returns:
#   1 if true, 0 false
#
###############################
sub isNumber {
    my ($self, $var) = @_;
    if ($var =~ /^[+-]?\d+$/) {
        return TRUE;
    }
    else {
        return FALSE;
    }
}

###############################
# trim -R emove blank spaces before and after string
#
# Arguments:
#   string
#
# Returns:
#   trimmed string
#
###############################
sub trim {
    my ($self, $string) = @_;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

###############################
# debugMsg - Print a debug message
#
# Arguments:
#   errorlevel - number compared to $self->opts->{debug}
#   msg        - string message
#
# Returns:
#   none
#
###############################
sub debugMsg {
    my ($self, $errlev, $msg) = @_;

    if ($self->opts->{debug} >= $errlev) {
        binmode STDOUT, ':encoding(utf8)';
        binmode STDIN,  ':encoding(utf8)';
        binmode STDERR, ':encoding(utf8)';

        print STDOUT "$msg\n";
    }
}

