my $pluginName = "@PLUGIN_NAME@";
if ($promoteAction ne '') {
    my @objTypes = ('projects', 'resources', 'workspaces');
    my $query    = $commander->newBatch();
    my @reqs     = map { $query->getAclEntry('user', "project: $pluginName", { systemObjectName => $_ }) } @objTypes;
    push @reqs, $query->getProperty('/server/ec_hooks/promote');
    $query->submit();

    foreach my $type (@objTypes) {
        if ($query->findvalue(shift @reqs, 'code') ne 'NoSuchAclEntry') {
            $batch->deleteAclEntry('user', "project: $pluginName", { systemObjectName => $type });
        }
    }

    if ($promoteAction eq "promote") {
        foreach my $type (@objTypes) {
            $batch->createAclEntry(
                                   'user',
                                   "project: $pluginName",
                                   {
                                      systemObjectName           => $type,
                                      readPrivilege              => 'allow',
                                      modifyPrivilege            => 'allow',
                                      executePrivilege           => 'allow',
                                      changePermissionsPrivilege => 'allow'
                                   }
                                  );
        }
    }
}

if ($upgradeAction eq "upgrade") {
    my $query   = $commander->newBatch();
    my $newcfg  = $query->getProperty("/plugins/$pluginName/project/labmanager_cfgs");
    my $oldcfgs = $query->getProperty("/plugins/$otherPluginName/project/labmanager_cfgs");
    my $creds   = $query->getCredentials("\$[/plugins/$otherPluginName]");

    local $self->{abortOnError} = 0;
    $query->submit();

    # if new plugin does not already have cfgs
    if ($query->findvalue($newcfg, 'code') eq 'NoSuchProperty') {

        # if old cfg has some cfgs to copy
        if ($query->findvalue($oldcfgs, 'code') ne 'NoSuchProperty') {
            $batch->clone(
                          {
                            path      => "/plugins/$otherPluginName/project/labmanager_cfgs",
                            cloneName => "/plugins/$pluginName/project/labmanager_cfgs"
                          }
                         );
        }
    }

    # Copy configuration credentials and attach them to the appropriate steps
    my $nodes = $query->find($creds);
    if ($nodes) {
        my @nodes = $nodes->findnodes('credential/credentialName');
        for (@nodes) {
            my $cred = $_->string_value;

            # Clone the credential
            $batch->clone(
                          {
                            path      => "/plugins/$otherPluginName/project/credentials/$cred",
                            cloneName => "/plugins/$pluginName/project/credentials/$cred"
                          }
                         );

            # Make sure the credential has an ACL entry for the new project principal
            my $xpath = $commander->getAclEntry(
                                                "user",
                                                "project: $pluginName",
                                                {
                                                   projectName    => $otherPluginName,
                                                   credentialName => $cred
                                                }
                                               );
            if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
                $batch->deleteAclEntry(
                                       "user",
                                       "project: $otherPluginName",
                                       {
                                          projectName    => $pluginName,
                                          credentialName => $cred
                                       }
                                      );
                $batch->createAclEntry(
                                       "user",
                                       "project: $pluginName",
                                       {
                                          projectName                => $pluginName,
                                          credentialName             => $cred,
                                          readPrivilege              => "allow",
                                          modifyPrivilege            => "allow",
                                          executePrivilege           => "allow",
                                          changePermissionsPrivilege => "allow"
                                       }
                                      );
            }

            # Attach the credential to the appropriate steps
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Provision',
                                        stepName      => 'Provision'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Cleanup',
                                        stepName      => 'Cleanup'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Command',
                                        stepName      => 'Command'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Snapshot',
                                        stepName      => 'Snapshot'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Revert',
                                        stepName      => 'Revert'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Capture',
                                        stepName      => 'Capture'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'ConfigurationChangeOwner',
                                        stepName      => 'ConfigurationChangeOwner'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Provision4.0',
                                        stepName      => 'Provision'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'CreateConfigurationFromVMTemplate',
                                        stepName      => 'CreateConfigurationFromVMTemplate'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'CreateConfigurationFromVMTemplate4.0',
                                        stepName      => 'CreateConfigurationFromVMTemplate'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Deploy',
                                        stepName      => 'Deploy'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'Clone',
                                        stepName      => 'Clone'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'CreateResourcesFromConfiguration',
                                        stepName      => 'CreateResourcesFromConfiguration'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'BulkCleanup',
                                        stepName      => 'BulkCleanup'
                                     }
                                    );
            $batch->attachCredential(
                                     "\$[/plugins/$pluginName/project]",
                                     $cred,
                                     {
                                        procedureName => 'CreateLMConnection',
                                        stepName      => 'CreateLMConnection'
                                     }
                                    );
        }
    }
}

# The plugin is being promoted, create a property reference in the server's property sheet
# Data that drives the create step picker registration for this plugin.
my %provision = (
    label       => "LabManager - Provision",
    procedure   => "Provision",
    description => "Provision a configuration.",
    category    => "Resource Management"
);
my %provision4 = (
    label       => "LabManager - Provision 4.0",
    procedure   => "Provision4.0",
    description => "Provision a configuration (LM 4.0 API).",
    category    => "Resource Management"
);
my %cleanup = (
    label       => "LabManager - Cleanup",
    procedure   => "Cleanup",
    description => "Cleanup a configuration.",
    category    => "Resource Management"
);
my %command = (
    label       => "LabManager - Command",
    procedure   => "Command",
    description => "Run any LabManager API command.",
    category    => "Resource Management"
);
my %snapshot = (
    label       => "LabManager - Snapshot",
    procedure   => "Snapshot",
    description => "Create a snapshot of a configuration or replace the existing one.",
    category    => "Resource Management"
);
my %revert = (
    label       => "LabManager - Revert",
    procedure   => "Revert",
    description => "Revert the configuration to the last snapshot.",
    category    => "Resource Management"
);
my %capture = (
    label       => "LabManager - Capture",
    procedure   => "Capture",
    description => "Capture a configuration and save it in LabManager library.",
    category    => "Resource Management"
);
my %changeowner = (
    label       => "LabManager - Change Owner",
    procedure   => "ConfigurationChangeOwner",
    description => "Change the owner of the given configuration.",
    category    => "Resource Management"
);
my %createfromvmtemplate = (
    label       => "LabManager - Create Configuration From VM Template",
    procedure   => "CreateConfigurationFromVMTemplate",
    description => "Create a configuration and add a VM based on a VM template.",
    category    => "Resource Management"
);
my %createfromvmtemplate4 = (
     label       => "LabManager - Create Configuration From VM Template 4.0",
     procedure   => "CreateConfigurationFromVMTemplate4.0",
     description => "Create a configuration and add a VM based on a VM template (LM 4.0 API).",
     category    => "Resource Management"
);
my %deploy = (
    label       => "LabManager - Deploy",
    procedure   => "Deploy",
    description => "Deploy a configuration.",
    category    => "Resource Management"
);
my %clone = (
    label       => "LabManager - Clone",
    procedure   => "Clone",
    description => "Clone a configuration.",
    category    => "Resource Management"
);
my %createresources = (
    label       => "LabManager - Create Resources From Configuration",
    procedure   => "CreateResourcesFromConfiguration",
    description => "Create resources from the virtual machines of a configuration.",
    category    => "Resource Management"
);
my %bulkcleanup = (
    label       => "LabManager - Bulk Cleanup",
    procedure   => "BulkCleanup",
    description => "Cleanup multiple configurations.",
    category    => "Resource Management"
);



$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Change Configuration Owner");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Create Connection");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Create From Template");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Create From Template 4.0");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Delete Connection");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Provision");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Provision 4.0");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Cleanup");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Command");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Snapshot");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Revert");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Capture");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - ConfigurationChangeOwner");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - CreateConfigurationFromVMTemplate");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - CreateConfigurationFromVMTemplate 4.0");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Deploy");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - Clone");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - CreateResourcesFromConfiguration");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - BulkCleanup");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - CloudManagerGrow");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/EC-LabManager - CloudManagerShrink");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Provision");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Provision 4.0");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Cleanup");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Command");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Snapshot");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Revert");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Capture");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Change Owner");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Create Configuration From VM Template");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Create Configuration From VM Template 4.0");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Deploy");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Clone");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Create Resources From Configuration");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/LabManager - Bulk Cleanup");;



@::createStepPickerSteps = (\%provision, \%provision4, \%cleanup, \%command, \%snapshot, \%revert, \%capture, \%changeowner, \%createfromvmtemplate, \%createfromvmtemplate4, \%deploy, \%clone, \%createresources, \%bulkcleanup);

