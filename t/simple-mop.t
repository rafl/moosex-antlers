use strict;
use warnings;
use Class::MOP;
use MooseX::Antlers::Recorder;

my $ar = MooseX::Antlers::Recorder->new;

$ar->instrument_routines('Class::MOP::Class::add_attribute');
$ar->instrument_sub_constructors('Class::MOP::Method::Generated::_eval_closure');

sub setup_class {

  my $foo_class = Class::MOP::Class->initialize("Foo");

  $foo_class->add_attribute('one',
    name => 'one', reader => 'get_one',
    writer => { set_one => sub { shift->{one} = shift } },
  );

  $foo_class->make_immutable;

  $foo_class;

}

my $foo_class = setup_class;

use Data::Dumper;
$Data::Dumper::Deparse = 1;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

print Dumper($foo_class);

print "\n---\n";

my $call = $ar->emit_call_results($foo_class);

#warn $call;

my ($save, $final) = eval $call;

die $@ if $@;

undef($foo_class);

Class::MOP::remove_metaclass_by_name("Foo");

{
  my $replay = sub { shift(@$save)->(@_) };

  no warnings 'redefine';

  local *Class::MOP::Class::add_attribute = $replay;

  local *Class::MOP::Class::make_immutable = sub {
    Class::MOP::store_metaclass_by_name('Foo', $_[0] = $final->());
  };

  $foo_class = setup_class;
}

print Dumper($foo_class);
