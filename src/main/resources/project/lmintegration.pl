#!/usr/bin/env perl
# -*-Perl-*-
#--------#---------#---------#---------#---------#---------#---------#---------#

# -----------------------------------------------------------------------------
# Copyright 2005-2010 Electric Cloud Corporation
#
#
# The following special keyword indicates that the "cleanup" script should
# scan this file for formatting errors, even though it doesn't have one of
# the expected extensions.
# CLEANUP: CHECK
#
# Copyright (c) 2005-2010 Electric Cloud, Inc.
# All rights reserved
# -----------------------------------------------------------------------------

$|=1;

# -------------------------------------------------------------------------
# Includes
# -------------------------------------------------------------------------
use ElectricCommander;
use ElectricCommander::Util;
use ElectricCommander::PropDB;
use ElectricCommander::PropMod;
use File::Spec;
use FindBin;
use List::Util qw[min];
use Getopt::Long;
use Time::Local;
use lib "$FindBin::Bin";
use warnings;
use strict;
use utf8;

# -------------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------------
use constant {
    SUCCESS       => 0,
    ERROR         => 1,
    
    DEFAULT_EC_PORT        => 8000,
    DEFAULT_EC_SECURE_PORT => 8443,
};

# -------------------------------------------------------------------------
# Globals
# -------------------------------------------------------------------------
$::gProgramName = "lmintegration";       # program name for errors

# -------------------------------------------------------------------------
# Options
# -------------------------------------------------------------------------
my $opts;
$opts->{JobStepId} = "1";                # JobStepId requesting provisioning
$opts->{Debug}     = 1;                  # debug level. higher gives more detail
$opts->{ec_server}= "";                  # ElectricCommander server
$opts->{ec_user}= "";                    # User for commander server
$opts->{ec_password}= "";                # Password for commander server
$opts->{ec_port} = "";                   # commander agent port
$opts->{ec_secureport} = "";             # commander secure agent port
$opts->{ec_usersecure} = 1;              # --ecsecure flag
$opts->{ec_timeout} = 180;               # commander timeout
$opts->{labmanager_server}= "localhost"; # LabManager server
$opts->{labmanager_user}= "";            # User for LabManager server
$opts->{labmanager_pass}= "";            # Password for LabManager server
$opts->{labmanager_org}= "default";      # Organizationname for LabManager server
$opts->{labmanager_cmd} = "";            # command to pass to LabManager
%{$opts->{labmanager_cmdargs}} = ();     # args to command
@{$opts->{LoadFiles}} = ();              # additional perl files to load
$opts->{mode} = "";                      # mode (provision, cleanup)
$opts->{Tag} = "";                       # Tag used to connect provision to cleanup
$opts->{SoapTimeout} = 300;              # timeout for soap call return. 5 min by def
$opts->{PingTimeout} = 300;              # timeout to wait for agent ping in secs
$opts->{Version} = 0;                    # --version flag
$opts->{Help} = 0;                       # --help flag
$opts->{results} = "";                   # property sheet to store results
$opts->{Test} = 0;                       # --test flag            


%::gOptions = (
   "mode=s"        => \$opts->{mode},
   "jobstepid=s"   => \$opts->{JobStepId},
   "tag=s"         => \$opts->{Tag},
   "ecserver=s"    => \$opts->{ec_server},
   "ecuser=s"      => \$opts->{ec_user},
   "ecpass=s"      => \$opts->{ec_password},
   "ecport=s"      => \$opts->{ec_port},
   "ecsecureport=s" => \$opts->{ec_secureport},
   "ecsecure"      => \$opts->{ec_usersecure},
   "ectimeout=s"   => \$opts->{ec_timeout},
   "lmserver=s"    => \$opts->{labmanager_server},
   "lmuser=s"      => \$opts->{labmanager_user},
   "lmpass=s"      => \$opts->{labmanager_pass},
   "lmorg=s"       => \$opts->{labmanager_org},
   "command=s"     => \$opts->{labmanager_cmd},
   "args=s"        => \%{$opts->{labmanager_cmdargs}},
   "load=s"        => \@{$opts->{LoadFiles}},
   "soaptimeout=s" => \$opts->{SoapTimeout},
   "pingtimeout=s" => \$opts->{PingTimeout},
   "version"       => \$opts->{Version},
   "debug=s"       => \$opts->{Debug},
   "help"          => \$::gHelp,
   "loadFromFile"  => \$opts->{LoadFromFile},
   "test"          => \$opts->{Test},
   "results=s"     => \$opts->{results},

    );

my $version;
if ( !defined( $version ) ) {
    $version = 'unpackaged';
}

$::gBanner = "Electric Cloud VMWare LabManager Integration version $version\n"
    . "Copyright (C) 2005-" . (1900 + (localtime())[5]) 
    . " Electric Cloud, Inc.\n"
    . "All rights reserved.\n";

# -------------------------------------------------------------------------
# Help
# -------------------------------------------------------------------------
$::gShortHelp = "Use \"$::gProgramName --help\" for more details";

$::gHelpMessage = "\n$::gBanner\nUsage:
$::gProgramName
--lmserver server                  LabManager server
--lmuser user                      LabManager user
--lmpass password                  LabManager password
--mode mode                        provision, cleanup, command
--command command                  command to run
--arg name=value                   args to command (can appear multiple times)
--tag tagName                      Unique tag for this provision/cleanup
--jobstepid                        jobstepid (for testing)
--ecserver server                  Commander server (for testing)
--ecport port                      Set the port the agent is using
--ecsecureport port                Set the secure port the agent is using
--ectimeout time                   Set the agent timeout
--ecsecure                         Use HTTPS to communicate with the ElectricCommander server
--ecuser user                      Commander user (for testing)
--ecpass password                  Commander password (for testing)
--soaptimeout time                 Override for the SOAP timout in miliseconds
--pingtimeout time                 Override for the PING timout in seconds
--load files                       Additional perl files to load (for testing)
--version                          Print Lab Manager Integration version number
--loadFromFile                     Debug mode... get LabManager.pm from filesystem
--test                             Test mode... ElectricCommander object created by tests
--results path                     The path to a property sheet for results (cannot use /myJob etc..)
";

###############################
# initializeECServer - Set initial values for Commander
#
# Arguments:
#   none
#
# Returns:
#   0 - success
#   1 - error
#
################################
sub initializeECServer {

    if ( (!defined($opts->{ec_server}) or $opts->{ec_server} eq "") and (!defined($ENV{"COMMANDER_SERVER"}) or $ENV{"COMMANDER_SERVER"} eq "") ) {
        print  "error: COMMANDER_SERVER not in environment or specified in command line\n";
        print  $::gShortHelp . "\n";
        return ERROR;
    }
    if (!defined($opts->{ec_server}) or $opts->{ec_server} eq "") {
        $opts->{ec_server} = $ENV{"COMMANDER_SERVER"};
    }
    if ( (!defined($opts->{ec_port}) or $opts->{ec_port} eq "") and (!defined($ENV{"COMMANDER_PORT"}) or $ENV{"COMMANDER_PORT"} eq "") ) {
        $opts->{ec_port} = DEFAULT_EC_PORT;
    }
    if (!defined($opts->{ec_port}) or $opts->{ec_port} eq "") {
        $opts->{ec_port} = $ENV{"COMMANDER_PORT"};
    }
    if ( (!defined($opts->{ec_secureport}) or $opts->{ec_secureport} eq "") and (!defined($ENV{"COMMANDER_HTTPS_PORT"}) or $ENV{"COMMANDER_HTTPS_PORT"} eq "") ) {
        $opts->{ec_secureport} = DEFAULT_EC_SECURE_PORT;
    }
    if (!defined($opts->{ec_secureport}) or $opts->{ec_secureport} eq "") {
        $opts->{ec_secureport} = $ENV{"COMMANDER_HTTPS_PORT"};
    }
    return SUCCESS;
}

###############################
# validateOptions - Validate input options
#
# Arguments:
#   none
#
# Returns:
#   0 - success
#   1 - error
#
################################
sub validateOptions() {
    
    if ( $opts->{JobStepId} eq ""  and $ENV{"COMMANDER_JOBSTEPID"} eq "") {
        print  "error: COMMANDER_JOBSTEPID not in  environment or specified in command line\n";
        print  $::gShortHelp . "\n";
        return ERROR;
    }
    if ($opts->{JobStepId} eq "") {
        $opts->{JobStepId} = $ENV{"COMMANDER_JOBSTEPID"};
    }
    if ($opts->{labmanager_user} eq "" or $opts->{labmanager_pass} eq "") {
        print  "error: LabManager user/pass not specified\n";
        print  $::gShortHelp . "\n";
        return ERROR;
    }
    if ($opts->{mode} eq "" ) {
        print "error: invalid mode\n";
        print $::gShortHelp . "\n";
        return ERROR;
    }
    if (($opts->{mode} eq "provision" or $opts->{mode} eq "cleanup") and $opts->{Tag} eq "") {
        print "error: tag required for provision and cleanup modes\n";
        print $$::gShortHelp . "\n";
        return ERROR;
    }
    $opts->{Tag} =~ 's/\//g';

    # create an option entry for each arg
    foreach my $o (keys %{$opts->{labmanager_cmdargs}}) {
        $opts->{$o} = $opts->{labmanager_cmdargs}{$o};
    }
    return SUCCESS;
}

###############################
# loadPluginFiles - Load and execute plugin perl files specified by --load option.
#
# Arguments:
#   none
#
# Returns:
#   none
#
################################
sub loadPluginFiles() {

    foreach my $file (@{$opts->{LoadFiles}}) {
        $file = File::Spec->rel2abs($file);
        if (!(do $file)) {
            my $message = $@;
            if (!$message) {
                # If the file isn't found no message is left in $@, but there is a message in $!.
                $message = "Cannot read file \"$file\": " . lcfirst($!);
            }
            die $message;
         }
     }
}

###############################
# main - Main subprocedure
#
# Arguments:
#   none
#
# Returns:
#   0 - success
#   1 - error
#
################################
sub main() {

    # ---------------------------------------------------------------
    # Process Options
    # ---------------------------------------------------------------
    if (!GetOptions(%::gOptions)) {
        debugMsg(0,$::gHelpMessage);
        exit ERROR;
    }
    if ($opts->{Version}) {
        print $::gBanner;
        exit SUCCESS;
    }
    if ($::gHelp) {
        print  $::gHelpMessage;
        return SUCCESS;
    }

    # log onto commander
    if (!$opts->{Test} ) {
        #initializeECServer();
        if (initializeECServer()) { exit ERROR;}
        ecServerLogin();
    }
    
    # ---------------------------------------------------------------
    #  load LabManager.pm from Commander
    # ---------------------------------------------------------------
    if ($opts->{LoadFromFile} ) {
        require LabManager;
    } else {

        # Load the actual code into this process
        if (!ElectricCommander::PropMod::loadPerlCodeFromProperty(
            $::gCommander,"/myProject/lm_driver/LabManager") ) {
            print "Could not load LabManager.pm\n";
            exit ERROR;
        }
    }

    # load test files if present
    loadPluginFiles();

    # ---------------------------------------------------------------
    # Validate options
    # ---------------------------------------------------------------
    if (validateOptions()) { exit ERROR;}

    $opts->{exitcode} = SUCCESS;

    my $lm = new LabManager($::gCommander,$opts);
    # ---------------------------------------------------------------
    # Dispatch operation
    # ---------------------------------------------------------------
    for ($opts->{mode})
    {
        # modes
        /command/i and do      { $lm->command(); last; };
        /provision/i and do    { $lm->provision(); last; };
        /cleanup/i and do      { $lm->cleanup(); last; };
    }

    exit($lm->ecode());
}

###############################
# ecServerLogin - Login to ElectricCommander
#
# Arguments:
#   none
#
# Returns:
#   none
#
################################
sub ecServerLogin {

    # -------------------------------------------------
    # Connect and login to Commander
    # -------------------------------------------------
    debugMsg(1, "Connecting to Commander server $opts->{ec_server}...");

    # Establish a connection to the Commander server, and set it to return
    # errors rather than aborting on them.

    $::gCommander = ElectricCommander->new({
            user        => $opts->{ec_user},
            server      => $opts->{ec_server},
            port        => $opts->{ec_port},
            securePort  => $opts->{ec_secureport},
            secure      => $opts->{ec_usersecure},
            timeout     => $opts->{ec_timeout},
            }
            );        
    $::gCommander->abortOnError(0);

    if (!$::gCommander->{sessionId} && !defined($ENV{ECLABMANAGER_TEST})) {
    
        if (!defined($opts->{ec_password}) || $opts->{ec_password} eq "") {
            # Retrieve the Commander user's password.
            $opts->{ec_password} = 
                ElectricCommander::Util::getPassword("Enter the password for Commander user $opts->{ec_user}: ");
        }   
        my $session = $::gCommander->login($opts->{ec_user}, $opts->{ec_password});
        my $responses = $session->find('//response');
        my $sessionId = "";
        foreach my $response ($responses->get_nodelist) {
            $sessionId = $session->findvalue('sessionId',$response);
        }
        if ($sessionId eq "") {
            debugMsg(0, "Error: logging on to server $opts->{ec_server} as $opts->{ec_user}");
            exit 2;
        }
    }
    
    # test connection
    my $ph = new ElectricCommander::PropDB($::gCommander,"");
    my $dataDir = $ph->getProp("/server/Electric Cloud/dataDirectory");
    
    if (defined ($dataDir)  && $dataDir ne "") {
        debugMsg(1, "Connected");
    } else {
        debugMsg(1, "Not connected");
            exit 2;
    }
}

###############################
# debugMsg - Print a debug message
#
# Arguments:
#   errorlevel - number compared to $opts->{Debug}
#   msg        - string message
#
# Returns:
#   none
#
################################
sub debugMsg($$) {
    my ($errlev, $msg) = @_;

    if ($opts->{Debug} >= $errlev) { print "$msg\n"; }
}

main();




