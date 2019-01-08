##########################
# cleanup.pl
##########################
use utf8;

my $opts;

$opts->{connection_config}        = "$[connection_config]";
$opts->{labmanager_org}           = q{$[labmanager_org]};
$opts->{labmanager_work}          = q{$[labmanager_work]};
$opts->{Tag}                      = q{$[tag]};
$opts->{results}                  = q{$[results]};
$opts->{save_configuration_name}  = q{$[save_configuration_name]};
$opts->{save_configuration_owner} = q{$[save_configuration_owner]};
$opts->{new_library_name}         = q{$[new_library_name]};
$opts->{destination_tag}          = q{$[destination_tag]};
$opts->{destination_results}      = q{$[destination_results]};
$opts->{labmanager_config}        = q{$[labmanager_config]};

$[/myProject/procedure_helpers/preamble]

$gt->cleanup();
exit($opts->{exitcode});
