use strict;
use warnings;
use Test::More qw(no_plan);

{
  my $built;

  sub reset_built { $built = {} }

  sub get_built { $built }

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

  do_stuff;
}

# we start off with an array of @_s, so each one looks like
#   [ { foo => $sub } ]
# so we need to say (if this is the first entry)
#   $seen{$sub} = [ 0, '$VAR1->[0]->{foo}' ];
#
# 

sub process_log {
  my ($log, $final) = @_;
  my %seen;
  my $log_index = 0;
  foreach my $entry (@$log) {
    my $dd = Data::Dumper->new([$entry]);
    $dd->Dump;
    my @seen = $dd->Seen;
    while (my ($name, $value, $whut) = splice(@seen, 0, 3)) {
      $seen{$value} = [ $log_index, $name ];
    }
    $log_index++;
  }

  my @save;
  my $value_index = 0;

  my $final_dump = do {
    my $_dump = Data::Dumper->can('_dump');
    local *Data::Dumper::_dump = sub {
      my ($s, $val, $name) = @_;
      if (ref($val) eq 'CODE') {
        if (my $seen = $seen{$val}) {
          my $val_str = "\$values[$value_index]";
          push(@{$save[$seen->[0]]}, "$val_str = ".$seen->[1]);
          $value_index++;
          return $val_str;
        } else {
          my ($pack, $name) = Class::MOP::get_code_info($val);
          if ($name !~ /__ANON__/) {
            return "\\&${pack}::${name}";
          }
        }
      warn "Coderef ${val} not recognised, only superman can save us!";
      }
      return $_dump->(@_);
    };
    local $Data::Dumper::Useperl = 1;
    Data::Dumper->new([ $final ])->Dump;
  };
  warn Dumper(\@save);
  #warn $final_dump;
  my @values;
  my @save_subs = map {
    if (defined $_) {
      do {
        my $code = eval q!sub {
  my $VAR1 = \@_;
!.join(";\n", @$_).q!
};!;
        die $@ if $@;
        $code;
      };
    } else {
      sub {};
    }
  } @save;
  my $dump_sub = eval qq!sub {my ${final_dump}}!;
  die $@ if $@;
  return (\@save_subs, $dump_sub);
}

is_deeply(setup_stuff(10, 11, 12), [ 10, 11, 12 ], "captures ok");

my @log;

wrap_subs(\@log, map { "main::build_$_" } qw(1 2 3));

is_deeply(setup_stuff(13, 14, 15), [ 13, 14, 15 ], "logged ok");

use Data::Dumper;

my ($save, $final) = process_log(\@log, get_built);

local $Data::Dumper::Deparse = 1;
warn Dumper($save);
warn Dumper($final);
