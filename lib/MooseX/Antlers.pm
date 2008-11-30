package MooseX::Antlers;

use strict;
use warnings;
use Moose ();

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
