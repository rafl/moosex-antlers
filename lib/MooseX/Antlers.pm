package MooseX::Antlers;

use strict;
use warnings;
use Moose ();
use B::Hooks::EndOfScope;
use Data::Dumper;
use namespace::clean; # remember -except => 'meta' if we acquire one

########
#
# DA PLAN
#
# Overview:
#
# When a file is compiled, save the symbol table and meta-effects of
# each metamodel call to lib/Module/Name.pma (perl module with antlers).
# On subsequent compilation, provided the .pma is up to date wrt the .pm,
# hijack the metamodel calls to read from the cache stored in the .pma
# file and replay the effects without following the logic.
#
# Since we only care about modules whose compilation process is
# deterministic (at least for the moment), so far as I can tell all
# we need to remember is:
#
#  $class_name (for metaclass)
#  $class_name + $attribute_name (for attributes)
#  $class_name + $method_name (for methods)
#
# and the order in which these calls were made - it can be assumed that
# the first call that affects a given attribute will always be first.
# To be entirely honest, we could probably literally just store the
# order but that approach faintly worries me fragility-wise.
#
# Initial target is attribute construction since the many tiny evals
# involved seem to be a major performance pain point, first sub-target
# is therefore the accessor generation.
#
# Why aren't we using .pmc?:
#
# Because ... primarily because gut feeling says that letting the .pm
# file start to load as normal and then call off to the .pma file is
# going to give me better control over what's going on. Also because
# the only code I've seen that really uses it is Module::Compile, which
# is crack fueled as all hell even for my tastes and doesn't really gain
# us anything.
#
# The one real justification I can see for avoiding pmcs is that we may
# want to be able to put the antler cache somewhere other than in the
# main lib tree (especially given that we're interested in compiling
# scripts) - but I think the key thing is to not stop ourselves from
# using them later if it turns out I was talking out my ass (again).

my %attribute_construction;
my $accessor_install_hijack;

{

  my $orig = Class::MOP::Attribute->can('install_accessors');

  no warnings 'redefine';

  *Class::MOP::Attribute::install_accessors = sub {
    my $self = shift;
    if (my $ac =
          $attribute_construction
            {$self->associated_class->name}
            {$self->name}) {
      if (my $code = shift(@$ac)) {
        return $ac->($self);
      }
    }
    if ($accessor_install_hijack) {
      return $accessor_install_hijack->($orig, $self, @_);
    }
    $self->$orig(@_);
  };
}

sub antler_file_name {
  my ($self, $file) = @_;
  my $antler_file = $file.'a'; # this should be smarter
  return $antler_file;
}

sub hijack_accessor_installation {
  my ($self, $target_class) = @_;
  my $accessor_install_unjack = $accessor_install_hijack;
  my %saved;
  on_end_of_scope {
    $self->unjack_accessor_installation(
      $accessor_install_unjack, \%saved
    );
  };
  $accessor_install_hijack = sub {
    my $orig = shift;
    my $self = shift;
    if ($self->associated_class->name eq $target_class) {
      {
        # no, this isn't a good way to do this. However it'll let us
        # try memoizing reader+writer+accessor for Moose without needing
        # any changes to Moose itself
        no warnings 'redefine';
        my $orig = Moose::Meta::Attribute->can('_eval_code');
        local *Moose::Meta::Attribute::_eval_code = sub {
          my ($self, $code) = @_;
          if ((my $attr = $self->associated_attribute)
                ->associated_class->name eq $target_class) {
            $saved{$attr->name}{$self->name} = $code;
          }
          $orig->(@_);
        };
      }
    }
  };
}

sub unjack_accessor_installation {
  my ($self, $accessor_install_unjack, $saved) = @_;
  $accessor_install_hijack = $accessor_install_unjack;
  {
    local $Data::Dumper::Indent = 1;
    warn Dumper(\$saved);
  }
}

1;
