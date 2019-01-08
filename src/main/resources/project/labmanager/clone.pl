##########################
# clone.pl
##########################
use utf8;

my $opts;

$opts->{connection_config} = "$[connection_config]";
$opts->{labmanager_org} = q{$[labmanager_org]};
$opts->{labmanager_work} = q{$[labmanager_work]};
$opts->{labmanager_config} = q{$[labmanager_config]};
$opts->{save_configuration_name} = q{$[labmanager_new_name]};
$opts->{save_configuration_owner} = q{$[labmanager_owner]};
$opts->{Tag} = q{$[tag]};
$opts->{results} = q{$[results]};

$[/myProject/procedure_helpers/preamble]

$gt->clone();
exit($opts->{exitcode});