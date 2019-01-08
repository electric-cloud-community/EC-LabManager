##########################
# createResourcesFromConfiguration.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};
$opts->{labmanager_config} = q{$[labmanager_config]};
$opts->{labmanager_pools} = q{$[labmanager_pools]};
$opts->{labmanager_workspace} = q{$[labmanager_workspace]};
$opts->{labmanager_vmlist} = q{$[labmanager_vmlist]};
$opts->{Tag} = q{$[tag]};
$opts->{results} = q{$[results]};
$opts->{labmanager_createresource} = q{1};

$[/myProject/procedure_helpers/preamble]

$gt->createResourcesFromConfiguration();
exit($opts->{exitcode});