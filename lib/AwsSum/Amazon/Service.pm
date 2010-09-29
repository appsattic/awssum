## ----------------------------------------------------------------------------

package AwsSum::Amazon::Service;
use Moose::Role;
use Moose::Util::TypeConstraints;

# some things required from the user
has 'access_key_id'    => ( is => 'rw', isa => 'Str' );
has 'secret_access_key' => ( is => 'rw', isa => 'Str' );

my $allowed = {
    region => {
        'us-east-1'      => 1,
        'us-west-1'      => 1,
        'eu-west-1'      => 1,
        'ap-southeast-1' => 1,
    },
};

# setup the all of the regions in AWS
enum 'Region' => qw(us-east-1 us-west-1 eu-west-1 ap-southeast-1);
has 'region' => ( is => 'rw', isa => 'Region', default => 'us-east-1' );

## ----------------------------------------------------------------------------
# helper functions specifically for Amazon services (not necessarily all of them)

# useful for EC2 and SimpleDB (and maybe others)
sub _amazon_add_flattened_array_to_params {
    my ($self, $name, $array) = @_;

    # count which key we're up to (start at 1)
    my $i = 1;

    # loop through everything, keep a number and save each key
    foreach my $item ( @$array ) {
        # this might be a scalar or a hash
        if ( ref $item eq 'HASH' ) {
            foreach my $key ( keys %$item ) {
                # if this is also an array, recurse over it
                if ( ref $item->{$key} eq 'ARRAY' ) {
                    $self->_amazon_add_flattened_array_to_params( "$name.$i.$key", $item->{$key} );
                }
                else {
                    # just add it
                    $self->set_param( "$name.$i.$key", $item->{$key} );
                }
            }
        }
        else {
            # scalar, so just add it
            $self->set_param( "$name.$i", $item );
        }
        # next item number
        $i++;
    }
}

## ----------------------------------------------------------------------------
1;
## ----------------------------------------------------------------------------
