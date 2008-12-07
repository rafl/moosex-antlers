package MooseX::Antlers::Recorder;

use strict;
use warnings;
use Data::Dumper ();

sub new {
  my $class = $_[0];
  $class = ref($class) if ref($class);
  bless({ log_index => 0 }, $class);
}

sub instrument_routines {
  my ($self, @names) = @_;
  foreach my $name (@names) {
    (my $pack = $name) =~ s/\::([^:]+)$//;
    my $sub = $1;
    my $orig = $pack->can($sub);
    $self->{saved_routines}{$name} = $orig;
    # Note: if we stored $new that would be a circular reference
    my $new = sub {
      $self->record_call([ @_ ]);
      $orig->(@_);
    };
    {
      no strict 'refs';
      no warnings 'redefine';
      *{$name} = $new;
    }
  }
}

sub deinstrument_routines {
  my ($self) = @_;
  my $save = $self->{saved_routines};
  foreach my $name (keys %$save) {
    no strict 'refs';
    no warnings 'redefine';
    # deleting the entries means saved_routines will be empty when we're done
    *{$name} = delete $save->{$name};
  }
}

# we get handed a ref to @_, like
#   [ { foo => $sub } ]
# so we need to say 
#   $seen{$sub} = [ 0, '$VAR1->[0]->{foo}' ];
# where 0 is the log_index

sub record_call {
  my ($self, $args) = @_;
  my $dd = Data::Dumper->new([$args]);
  $dd->Dump;
  my @seen = $dd->Seen;
  while (my ($name, $value, $whut) = splice(@seen, 0, 3)) {
    $self->{seen}{$value} = [ $self->{log_index}, $name ];
  }
  $self->{log_index}++;
}

# to emit, what we do is cross-reference the seen values
# so for the first value we find in the output, we emit
#   $values[0]
# into the dumper stream, and add
#   $values[0] = $VAR1->[0]{foo}
# to the arrayref of code fragments for call 0 ($save[0])
#
# then we build subs of the form
#   sub { my $VAR1 = \@_; $values[0] = $VAR1->[0]{foo} }
# that close over an @values shared with the final reconstruction code
# so by the time it runs all the @values entries are populated with the
# user-provided refs
#
# any sub that isn't in the seen list we hope the user put in the symbol
# table and if we it has a full name try and get it from there; if it's not
# there either then warn because we're probably fucked

sub emit_call_results {
  my ($self, $final) = @_;
  my @save;
  my $value_index = 0;
  my $final_dump = do {
    my $_dump = Data::Dumper->can('_dump');
    local *Data::Dumper::_dump = sub {
      my ($s, $val, $name) = @_;
      if (ref($val) eq 'CODE') {
        if (my $seen = $self->{seen}->{$val}) {
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
    local $Data::Dumper::Indent = 1;
    Data::Dumper->new([ $final ])->Dump;
  };
  #warn Dumper(\@save);
  #warn $final_dump;
  my @save_subs = map {
    if (defined $_) {
      my $code = q!sub {
  my $VAR1 = \@_;
!.join(";\n", @$_).q!
}!;
    } else {
      'undef';
    }
  } @save;
  my $dump_sub = qq!sub {my ${final_dump}}!;
  return q!my @values;
[
!.join(', ', @save_subs).q!
],
!.$dump_sub.q!
;
!;
}

1;
