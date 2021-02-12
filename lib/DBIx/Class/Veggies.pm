package DBIx::Class::Veggies;

# VERSION

use strictures 2;
use Import::Into ();
use Sub::Util qw/set_subname/;
use Lingua::EN::PluralToSingular ();
require DBIx::Class::Candy;

sub import {
    my ($pkg, %args) = @_;
    $args{'-autotable'} //= v1;
    DBIx::Class::Candy->import::into(1, %args);

    # Here, we grab Candy's helpers, before they get cleaned up by
    # namespace::clean from the caller, and export our own helpers
    my $caller = caller;
    my ($base_pkg, $pkg_table) = $caller =~ /(.+::Result::)(.+)$/;
    my $set_sub = sub {
        my ($name, $code) = @_;
        no strict 'refs';
        *{"$caller\::$name"} = set_subname $name => $code;
    };

    my $sub_primary_column = $caller->can('primary_column');
    $set_sub->(pcol => sub {
        my ($col_name, $conf) = @_;
        $sub_primary_column->(
            $col_name,
            { data_type => 'int', is_auto_increment => 1, %{$conf||{}} }
        )
    });

    my $sub_column = $caller->can('column');
    for my $sub (
        [col  => 'TEXT'], [ucol => 'INTEGER UNSIGNED'],
        [tcol => 'TEXT'], [icol => 'INTEGER' ], [vcol => 'VARCHAR'],
    ) {
        $set_sub->($sub->[0] => sub {
            my ($col_name, $conf) = @_;
            $sub_column->($col_name, { data_type => $sub->[1], %{$conf||{}} })
        })
    }

    my $sub_belongs_to = $caller->can('belongs_to');
    $set_sub->(owned_by => sub {
        my ($col_name, @conf) = @_;
        if (@conf) {
            $sub_belongs_to->($col_name, @conf)
        }
        else {
            my $id_col = _idify_col($col_name);
            $sub_column->($id_col, { data_type => 'INTEGER' });
            $sub_belongs_to->(
                $col_name,
                _pkgify_col($col_name, $base_pkg),
                $id_col,
            )
        }
    });

    my $sub_has_many = $caller->can('has_many');
    $set_sub->(owns => sub {
        my ($col_name, @conf) = @_;
        my $singular = Lingua::EN::PluralToSingular::to_singular($col_name);
        $sub_has_many->(
            $col_name,
            @conf ? @conf : (
                _pkgify_col($singular, $base_pkg),
                _idify_col(lc $pkg_table),
            )
        )
    });

    $set_sub->(uniquely => sub { $caller->add_unique_constraint(@_) });
}

sub _pkgify_col {
    my ($col_name, $base_pkg) = @_;
    $base_pkg . (ucfirst($col_name) =~ s/_(.)/uc $1/egr);
}

sub _idify_col {
    my $col_name = shift;
    ($col_name =~ /_id$/) ? $col_name : "${col_name}_id"
}

1

__END__

=pod

=head1 NAME

DBIx::Class::Veggies - A DBIx::Class::Candy that's healthier for your fingers

=head1 SYNOPSIS

    package MyApp::Schema::Result::Artist;

    use DBIx::Class::Veggies;

    pcol 'artist_id';    # INT primary column, with auto increment
    col  'name';         # TEXT column
    vcol stage_name => { # VARCHAR column, with standard DBIx::Class settings
        size => 25,
        is_nullable => 1,
    };

    # Same as `has_many albums => 'A::Schema::Result::Album', 'artist_id'`:
    owns 'albums';

    1;

=head1 DESCRIPTION

C<DBIx::Class::Veggies> defines additional helpers to those provided
by L<DBIx::Class::Candy>, which provide for shorter typing with set defaults.

=head1 IMPORT OPTIONS

The module imports L<DBIx::Class::Candy> into your namespace, making available
all of its features.

This includes the import arguments, which by default include
C<< -autotable => v1 >>

    use DBIx::Class::Veggies;

Is a superset of doing:

    use DBIx::Class::Candy -autotable => v1;

You get Candy's features, plus additional helpers. The available
L<DBIx::Class::Candy/IMPORT-OPTIONS> work:

    use DBIx::Class::Veggies
        -autotable    => 'singular',
        -experimental => ['signatures'];

=head1 HELPERS

All of L<DBIx::Class::Candy>'s helpers are available to you. In addition,
the module provides the following extras:

=head2 C<pcol>

Alias for L<DBIx::Class::Candy>'s C<primary_column>, with the default
C<data_type> set to C<int> and C<is_auto_increment> set to C<1>. Note that
you can override both of those values by providing your own:

    pcol 'prod_id';

Is equivalent to:

    primary_column prod_id => {
        data_type => 'int',
        is_auto_increment => 1,
    }

And you can override values:

    primary_column prod_id => {
        data_type => 'INT UNSIGNED',
        is_auto_increment => 0,
    }

=head2 C<col>

Alias for L<DBIx::Class::Candy>'s C<column>, with the default C<data_type>
set to C<TEXT>. Note that you can override that C<data_type> by providing
your own.

    col 'foo';

Is equivalent to:

    column foo => { data_type => 'TEXT' }

And you can override:

    col foo => { data_type => 'INTEGER' }

=head2 C<tcol>

Alias for C<col>. Mnemonic I<text column>.

=head2 C<icol>

Alias for C<col>, with C<INTEGER> as the default C<data_type>.
Mnemonic I<integer column>.

=head2 C<ucol>

Alias for C<col>, with C<INTEGER UNSIGNED> as the default C<data_type>.
Mnemonic I<unsigned integer column>.

=head2 C<vcol>

Alias for C<col>, with C<VARCHAR> as the default C<data_type>.
Mnemonic I<varchar column>.

=head2 C<owns>

Alias for L<DBIx::Class::Candy>'s C<has_many>, where the single-arg version
has special behaviour:

    package API::Result::Order;
    ...
    owns 'products';

Is equivalent to:

    package API::Result::Order;
    ...
    has_many products => 'API::Result::Product' => 'order_id';

The given argument becomes the accessor name and is singularized to create
the relationship package name, and our own package name is used to create the
`foo_id` column name for the key in the foreign table where we store our
primary key.

=head2 C<owned_by>

Alias for L<DBIx::Class::Candy>'s C<belongs_to>, where the single-arg version
has special behaviour:

    package API::Result::Product;
    ...
    owned_by 'order';

Is equivalent to:

    package API::Result::Product;
    ...
    icol 'order_id';
    belongs_to order => 'API::Result::Order' => 'order_id';

The given argument is becomes the accessor name and is used
to create the relationship package name, along with the `foo_id` column name
for the foreign key in our table, where we store the primary key.

=head2 C<uniquely>

Alias for L<DBIx::Class::ResultSource/add_unique_constraint>:

    uniquely constraint_name => [qw/column1 column2/];

Is equivalent to:

    __PACKAGE__->add_unique_constraint(
        constraint_name => [ qw/column1 column2/ ],
    );
