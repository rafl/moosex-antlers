package MooseX::Antlers::Recorder;

use strict;
use warnings;
use Data::Dumper ();
use Sub::Identify ();

sub new {
  my $class = $_[0];
  $class = ref($class) if ref($class);
  bless({ log_index => 0 }, $class);
}

sub instrument_routines {
  my ($self, @names) = @_;
  push(@{$self->{tracked_routines}}, @names);
  $self->_instrument_calls(
    sub {
      my $orig = shift;
      sub {
        # we keep $copy in scope because otherwise the refaddr can get
        # re-used, thus completely messing up the $builder stuff.
        # of course, this indicates we may be screwed by this some other
        # way at some later point, which probably indicates we need to
        # use Variable::Magic or Scalar::Annotate to tag buildables.
        #
        # also, undef-ify $self because otherwise we just bind that as
        # part of the seen list and try and replace the entire final
        # construction with it. which is pointless.

        my $copy = [ undef, @_[1..$#_] ];
        $self->record_call($copy);
        $orig->(@_);
      };
    },
    @names
  );
}

sub _instrument_calls {
  my ($self, $builder, @names) = @_;
  foreach my $name (@names) {
    (my $pack = $name) =~ s/\::([^:]+)$//;
    my $sub = $1;
    my $orig = $pack->can($sub);
    die "Couldn't find ${pack}->${sub}" unless $orig;
    $self->{saved_routines}{$name} = $orig;
    # Note: if we stored $new that would be a circular reference
    my $new = $builder->($orig, $pack);
    {
      no strict 'refs';
      no warnings 'redefine';
      *{$name} = $new;
    }
  }
}

sub instrument_sub_constructors {
  my ($self, @names) = @_;
  $self->_instrument_calls(
    sub {
      my ($orig, $pack) = @_;
      sub {
        my ($obj, $captures, $body) = @_;
        my $cr = $orig->(@_);
        $self->record_coderef_construction($captures, $body, $cr, $pack);
        return $cr;
      };
    },
    @names
  );
}

# hardcoded target because nothing else really makes sense
# - the above method should probably hardcode to _eval_closure too

sub instrument_method_installation {
  my $self = shift;
  $self->_instrument_calls(
    sub {
      my ($orig) = @_;
      sub {
        my ($obj, $target, $initial_value) = @_;
        if ($target->{sigil} eq '&') {
          my $name = $obj->{'package'}.'::'.$target->{name};
          $self->record_coderef_installation($name, $initial_value);
        }
        $orig->(@_);
      };
    },
    'Class::MOP::Package::add_package_symbol'
  );
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
    my $index = $self->{log_index};
    $self->{buildable}{$value} = $self->build_seen_handler($index, $name);
  }
  $self->{log_index}++;
}

sub build_seen_handler {
  my ($self, $index, $name) = @_;
  return sub {
    my $save = $self->{save_during_replay};
    my $val_str = $self->next_values_member;
    push(@{$save->[$index]}, "$val_str = ".$name);
    return $val_str;
  };
}

sub record_coderef_construction {
  my ($self, $captures, $body, $coderef, $package) = @_;
  $self->{buildable}{$coderef} = sub {
    my $constructors = $self->{coderef_constructors};
    my $val_str = $self->next_values_member;
    my $captures_dump = $self->with_custom_dumper_do($captures, '$__captures');
    $captures_dump = 'my $__captures; '.$captures_dump;
    my $serialise_captures = $self->build_capture_constructor($captures);
    push(@$constructors,
      q!sub { !
        .$captures_dump
        .$serialise_captures
        .$val_str.q! = do { package !.$package.q!; !
                            .$body.q! }; }!
    );
    return $val_str;
  }
}

sub record_coderef_installation {
  my ($self, $name, $code) = @_;
  $self->{coderef_installs}{$name} = "$code";
}

sub build_capture_constructor {
  my ($self, $captures) = @_;
  join(
    "\n",
    (map {
      /^([\@\%\$])/ or die "capture key should start with \@, \% or \$: $_";
      q!my !.$_.q! = !.$1.q!{$__captures->{'!.$_.q!'}};!;
    } keys %$captures),
    '' # trailing \n
  );
}

sub next_values_member {
  my ($self) = @_;
  my $value_index = $self->{value_map_index};
  my $val_str = "\$values[$value_index]";
  $self->{value_map_index}++;
  return $val_str;
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
  local $self->{value_mapback} = {};
  local $self->{value_map_index} = 0;
  local $self->{save_during_replay} = [];
  local $self->{coderef_constructors} = [];
  my $final_dump = $self->with_custom_dumper_do($final);
  my @save_subs = map {
    if (defined $_) {
      my $code = q!sub {
  my $VAR1 = \@_;
!.join(";\n", @$_).q!
}!;
    } else {
      'undef';
    }
  } @{$self->{save_during_replay}};
  #warn join("\n----\n", @save_subs);
  #warn join("\n----\n", @{$self->{coderef_constructors}});

  my @installs;
  {
    my $values = $self->{value_mapback};
    foreach my $name (keys %{$self->{coderef_installs}}) {
      my $val = $self->{coderef_installs}{$name};
      my $val_str = $values->{$val};
      unless ($val_str) {
        if (my $builder = $self->{buildable}->{$val}) {
          $val_str = $values->{$val} = $builder->();
        } else {
          die "Coderef ${val} installed to ${name} but no idea where it came from";
        }
      }
      push(@installs, "*${name} = ${val_str};");
    }
  }
  
  my $dump_sub = q!sub {
    !.join("\n",
        (map { "$_->();" } @{$self->{coderef_constructors}}),
        @installs,
    ).qq!
    my \$VAR1; ${final_dump}; \$VAR1;
  }!;
#warn $dump_sub;
  return q!my @values;
[
!.join(', ', @save_subs).q!
],
!.$dump_sub.q!
;
!;
}

sub with_custom_dumper_do {
  my ($self, $value, $name) = @_;
  my $_dump = Data::Dumper->can('_dump');
  local $self->{dumper_fixups} = [];
  no warnings 'redefine';
  local *Data::Dumper::_dump = sub {
    $self->dumper_handler($_dump, @_);
  };
  local $Data::Dumper::Useperl = 1;
  local $Data::Dumper::Indent = 1;
  $name ||= '$VAR1';
  local $self->{dumping_as} = $name;
  Data::Dumper->new([ $value ], [ $name ])->Dump
    .join("\n", @{$self->{dumper_fixups}});
}
  

sub dumper_handler {
  my $self = shift;
  my $_dump = shift;
  my ($s, $val, $name) = @_;
  my $values = $self->{value_mapback};
  my $save = $self->{save_during_replay};
  if (ref($val)) {
    if (my $builder = $self->{buildable}->{$val}) {
      return $values->{$val} ||= $builder->();
    }
  }
  if (ref($val) eq 'CODE') {
    my ($pack, $name) = Sub::Identify::get_code_info($val);
    if ($name !~ /__ANON__/) {
      return "\\&${pack}::${name}";
    }
    warn "Coderef ${val} not recognised, only superman can save us!";
  }
  my $result = $_dump->(@_);
  my $as = $self->{dumping_as};
  if ($result =~ /^${\quotemeta $as}/) {
    push(@{$self->{dumper_fixups}}, "${name} = ${result};");
    return 'undef';
  }
  return $result;
}

1;
