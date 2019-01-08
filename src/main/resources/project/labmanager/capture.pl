##########################
# capture.pl
##########################
use utf8;

my $opts;

$opts->{connection_config}   = "$[connection_config]";
$opts->{labmanager_org}      = q{$[labmanager_org]};
$opts->{labmanager_work}     = q{$[labmanager_work]};
$opts->{Tag}                 = q{$[tag]};
$opts->{results}             = q{$[results]};
$opts->{new_library_name}    = q{$[new_library_name]};
$opts->{destination_tag}     = q{$[destination_tag]};
$opts->{destination_results} = q{$[destination_results]};
$opts->{labmanager_config}   = q{$[labmanager_config]};

$[/myProject/procedure_helpers/preamble]

$gt->capture();
exit($opts->{exitcode});
