package Foo;

my $meta = Class::MOP::Class->initialize(__PACKAGE__);

$meta->add_attribute('one',
  name => 'one', reader => 'get_one',
  writer => { set_one => sub { $_[0]->{one} = $_[1] } },
);

$meta->make_immutable;

$meta;
