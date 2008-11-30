package MooseX::Antlers;

use strict;
use warnings;
use Moose ();

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
    $self->$orig(@_);
  };
}

1;
