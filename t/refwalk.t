use strict;
use warnings;
use Test::More qw(no_plan);

use MooseX::Antlers::Recorder;

{
  my $built;

  sub reset_built { $built = {} }

  sub get_built { $built }

  sub set_built { $built = shift }

  sub build_1 {
    my ($in) = @_;
    $built->{foo}{bar} = $in->{sub1};
  }

  sub build_2 {
    my ($in) = @_;
    $built->{quux} = $in->[2]{sub2};
  }

  sub build_3 {
    my ($in) = @_;
    $built->{ary} = [ 1, $in->{three}{sub3} ];
  }

  sub do_stuff {
    [
      $built->{foo}{bar}(),
      $built->{quux}(),
      $built->{ary}->[1]->(),
    ]
  }
}

sub wrap_subs {
  my $log = shift;
  my @names = @_;
  foreach my $name (@names) {
    (my $pack = $name) =~ s/\::([^:]+)$//;
    my $sub = $1;
    my $orig = $pack->can($sub);
    my $new = sub {
      push(@$log, [ @_ ]);
      $orig->(@_);
    };
    {
      no strict 'refs';
      no warnings 'redefine';
      *{$name} = $new;
    }
  }
}
  
sub setup_stuff {

  reset_built;

  my ($x, $y, $z);

  my ($sub1, $sub2, $sub3) = (sub { $x }, sub { $y }, sub { $z });

  # I'm using & here to ensure the calls are resolved at runtime

  &build_1({ sub1 => $sub1 });
  &build_2([ 0, 0, { sub2 => $sub2 } ]);
  &build_3({ three => { sub3 => $sub3 } });

  ($x, $y, $z) = @_;

}

setup_stuff(10, 11, 12);

is_deeply(do_stuff(), [ 10, 11, 12 ], "captures ok");

my $rec = MooseX::Antlers::Recorder->new;

$rec->instrument_routines(map { "main::build_$_" } qw(1 2 3));

setup_stuff(13, 14, 15);

is_deeply(do_stuff(13, 14, 15), [ 13, 14, 15 ], "logged ok");

#use Data::Dumper;

#warn Dumper($rec);

my $results = $rec->emit_call_results(get_built);

#warn $results;

my ($save, $final) = eval $results;

die $@ if $@;

#use Data::Dumper;
#$Data::Dumper::Deparse = 1;
#warn Dumper($save);
#warn Dumper($final);

{
  my $save_user = sub {
    if (my $code = shift(@$save)) {
      $code->(@_);
    }
  };
  no warnings 'redefine';
  local *build_1 = $save_user;
  local *build_2 = $save_user;
  local *build_3 = $save_user;

  setup_stuff(14, 15, 16);
}

set_built($final->());

is_deeply(do_stuff(), [ 14, 15, 16 ], "replay ok");
