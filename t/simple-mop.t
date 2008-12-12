use strict;
use warnings;
use Class::MOP;
use MooseX::Antlers::Recorder;

my $ar = MooseX::Antlers::Recorder->new;

$ar->instrument_routines('Class::MOP::Class::add_attribute');
$ar->instrument_sub_constructors('Class::MOP::Method::Generated::_eval_closure');

my $foo_class = Class::MOP::Class->initialize("Foo");

$foo_class->add_attribute('one',
  name => 'one', reader => 'get_one',
  writer => { set_one => sub { shift->{one} = shift } },
);

$foo_class->make_immutable;

use Data::Dumper;
$Data::Dumper::Deparse = 1;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
print Dumper($foo_class);

print $ar->emit_call_results($foo_class);
