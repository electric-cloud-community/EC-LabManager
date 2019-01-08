##########################
# createConfigurationFromVMTemplate.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};

$opts->{labmanager_name} = q{$[labmanager_name]};
$opts->{labmanager_description} = q{$[labmanager_description]};
$opts->{labmanager_vmtemplates} = q{$[labmanager_vmtemplates]};
$opts->{labmanager_vmnames} = q{$[labmanager_vmnames]};
$opts->{labmanager_boot_seq} = q{$[labmanager_boot_seq]};
$opts->{labmanager_boot_delay} = q{$[labmanager_boot_delay]};

$opts->{labmanager_fencedmode} = q{$[labmanager_fencedmode]};
$opts->{labmanager_createresource} = q{$[labmanager_createresource]};
$opts->{labmanager_pools} = q{$[labmanager_pools]};
$opts->{labmanager_workspace} = q{$[labmanager_workspace]};
$opts->{labmanager_state} = q{$[labmanager_state]};
$opts->{labmanager_physical_network} = q{$[labmanager_physical_network]};

$opts->{Tag} = q{$[Tag]};
$opts->{results} = q{$[results]};

# Specify minimum Lab Manager version
$opts->{labmanager_version} = "";

$[/myProject/procedure_helpers/preamble]

$gt->createConfigurationFromVMTemplate();
exit($opts->{exitcode});