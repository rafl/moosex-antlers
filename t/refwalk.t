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

  sub build_4 {
    my ($in) = @_;
    &build_4_crmaker('x', { '$foo' => \$in->{aryref} }, q!sub { $foo }!);
  }

  sub build_4_crmaker {
    my ($obj, $__captures, $body) = @_;
    $built->{sub} = do {
      my $code =
        MooseX::Antlers::Recorder->build_capture_constructor($__captures)
        .$body
      ;
      my $cr = eval $code;
      die "code $code, error $@" if $@;
      $cr;
    };
  }

  sub do_stuff {
    [
      $built->{foo}{bar}(),
      $built->{quux}(),
      $built->{ary}->[1]->(),
      $built->{sub}(),
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

  my ($x, $y, $z, $ary);

  $ary = [];

  my ($sub1, $sub2, $sub3) = (sub { $x }, sub { $y }, sub { $z });

  # I'm using & here to ensure the calls are resolved at runtime

  &build_1({ sub1 => $sub1 });
  &build_2([ 0, 0, { sub2 => $sub2 } ]);
  &build_3({ three => { sub3 => $sub3 } });
  &build_4({ aryref => $ary });

  ($x, $y, $z) = @_;

  push(@$ary, @{$_[3]}); # fourth element of @_
}

setup_stuff(10, 11, 12, [ 1, 2, 3 ]);

is_deeply(do_stuff(), [ 10, 11, 12, [ 1, 2, 3 ] ], "captures ok");

my $rec = MooseX::Antlers::Recorder->new;

$rec->instrument_routines(map { "main::build_$_" } qw(1 2 3 4));
$rec->instrument_sub_constructors("main::build_4_crmaker");

setup_stuff(13, 14, 15, [ 4, 5, 6 ]);

is_deeply(do_stuff(13, 14, 15), [ 13, 14, 15, [ 4, 5, 6 ] ], "logged ok");

#use Data::Dumper;

#warn Dumper($rec);

my $results = $rec->emit_call_results(get_built);

#warn $results;

my ($save, $final) = eval $results;

die $@ if $@;

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
  local *build_4 = $save_user;

  setup_stuff(14, 15, 16, [ 7, 8, 9 ]);
}

set_built($final->());

#use Data::Dumper;
#$Data::Dumper::Deparse = 1;
#warn Dumper(get_built);
#warn Dumper($save);
#warn Dumper($final);

is_deeply(do_stuff(), [ 14, 15, 16, [ 7, 8, 9 ] ], "replay ok");
