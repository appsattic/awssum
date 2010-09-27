## ----------------------------------------------------------------------------

package AwsSum::Amazon::EC2;

use Moose;
use Moose::Util::TypeConstraints;
with qw(
    AwsSum::Service
    AwsSum::Amazon::Service
);

use Carp;
use DateTime;
use List::Util qw( reduce );
use Digest::SHA qw (hmac_sha1_base64 hmac_sha256_base64);
use XML::Simple;
use URI::Escape;

my $allowed = {
    # From: http://docs.amazonwebservices.com/AWSEC2/latest/DeveloperGuide/index.html?instance-types.html
    'instance-type' => {
        'm1.small'    => 1,
        'm1.large'    => 1,
        'm1.xlarge'   => 1,
        't1.micro'    => 1,
        'c1.medium'   => 1,
        'c1.xlarge'   => 1,
        'm2.xlarge'   => 1,
        'm2.2xlarge'  => 1,
        'm2.4xlarge'  => 1,
        'cc1.4xlarge' => 1,
    },
};

## ----------------------------------------------------------------------------
# setup details needed or pre-determined

# some things required from the user
enum 'SignatureMethod' => qw(HmacSHA1 HmacSHA256);
has 'signature_method'   => ( is => 'rw', isa => 'SignatureMethod', default => 'HmacSHA256' );

# constants
sub version { '2010-08-31' }

# internal helpers
has '_command' => ( is => 'rw', isa => 'HashRef' );

## ----------------------------------------------------------------------------

my $commands = {
    # In order of: http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/index.html?OperationList-query.html

    # Amazon DevPay
    # * ConfirmProductInstance
    # AMIs
    # * CreateImage
    # * DeregisterImage
    # * DescribeImageAttribute
    # * DescribeImages
    # * ModifyImageAttribute
    # Availability Zones and Regions
    # * DescribeAvailabilityZones
    # * DescribeRegions
    # Elastic Block Store
    # * AttachVolume
    # * CreateSnapshot
    # * CreateVolume
    # * DeleteSnapshot
    # * DeleteVolume
    # * DescribeSnapshotAttribute
    # * DescribeSnapshots
    # * DescribeVolumes
    # * DetachVolume
    # * ModifySnapshotAttribute
    # * ResetSnapshotAttribute
    # Elastic IP Addresses
    # * AllocateAddress
    # * AssociateAddress
    # * DescribeAddresses
    # * DisassociateAddress
    # * ReleaseAddress
    # General
    # * GetConsoleOutput
    # Images
    # * RegisterImage
    # * ResetImageAttribute
    # Instances
    # * DescribeInstanceAttribute
    # * DescribeInstances
    # * ModifyInstanceAttribute
    # * RebootInstances
    # * ResetInstanceAttribute
    # * RunInstances
    # * StartInstances
    # * StopInstances
    # * TerminateInstances
    # Key Pairs
    # * CreateKeyPair
    # * DeleteKeyPair
    # * DescribeKeyPairs
    # * ImportKeyPair
    # Monitoring
    # * MonitorInstances
    # * UnmonitorInstances
    # Placement Groups
    # * CreatePlacementGroup
    # * DeletePlacementGroup
    # * DescribePlacementGroups
    # Reserved Instances
    # * DescribeReservedInstances
    # * DescribeReservedInstancesOfferings
    # * PurchaseReservedInstancesOffering
    # Security Groups
    # * AuthorizeSecurityGroupIngress
    # * CreateSecurityGroup
    # * DeleteSecurityGroup
    # * DescribeSecurityGroups
    # * RevokeSecurityGroupIngress
    # Spot Instances
    # * CancelSpotInstanceRequests
    # * CreateSpotDatafeedSubscription
    # * DeleteSpotDatafeedSubscription
    # * DescribeSpotDatafeedSubscription
    # * DescribeSpotInstanceRequests
    # * DescribeSpotPriceHistory
    # * RequestSpotInstances
    # Tags
    # * CreateTags
    # * DeleteTags
    # * DescribeTags
    # Windows
    # * BundleInstance
    # * CancelBundleTask
    # * DescribeBundleTasks
    # * GetPasswordData

    # Availability Zones and Regions
    'DescribeAvailabilityZones' => {
        name           => 'DescribeAvailabilityZones',
        method         => 'describe_availability_zones',
        params         => {},
    },
    'DescribeRegions' => {
        name           => 'DescribeRegions',
        method         => 'describe_regions',
        params         => {},
    },

    # Elastic IP Addresses
    'AllocateAddress' => {
        name           => 'AllocateAddress',
        method         => 'allocate_address',
        params         => {},
    },
    'DescribeAddresses' => {
        name           => 'DescribeAddresses',
        method         => 'describe_addresses',
        params         => {},
    },
    'ReleaseAddress' => {
        name           => 'ReleaseAddress',
        method         => 'release_address',
        params         => {},
        opts           => [ 'PublicIp=s' ],
    },

    # Security Groups
    'CreateSecurityGroup' => {
        name           => 'CreateSecurityGroup',
        method         => 'create_security_group',
        params         => {},
        opts           => [ 'GroupName=s', 'GroupDescription=s' ],
    },
    'DeleteSecurityGroup' => {
        name           => 'DeleteSecurityGroup',
        method         => 'delete_security_group',
        params         => {},
        opts           => [ 'GroupName=s' ],
    },
    'DescribeSecurityGroups' => {
        name           => 'DescribeSecurityGroups',
        method         => 'describe_security_groups',
        params         => {},
    },
};

## ----------------------------------------------------------------------------
# things to fill in to fulfill AwsSum::Service

sub commands { $commands }
sub verb { 'get' }
sub url {
    my ($self) = @_;

    # From: http://docs.amazonwebservices.com/AWSEC2/latest/DeveloperGuide/index.html?using-query-api.html
    return q{https://ec2.} . $self->endpoint . q{.amazonaws.com/};
}
sub host {
    my ($self) = @_;
    return q{ec2.} . $self->endpoint . q{.amazonaws.com};
}
sub code { 200 }

sub sign {
    my ($self) = @_;

    my $date = DateTime->now( time_zone => 'UTC' )->strftime("%Y-%m-%dT%H:%M:%SZ");

    # add the service params first before signing
    $self->set_param( 'Action', $self->_command->{name} );
    $self->set_param( 'Version', $self->version );
    $self->set_param( 'AWSAccessKeyId', $self->access_key_id );
    $self->set_param( 'Timestamp', $date );
    $self->set_param( 'SignatureVersion', 2 );
    $self->set_param( 'SignatureMethod', $self->signature_method );

    # See: http://docs.amazonwebservices.com/AWSEC2/2010-08-31/DeveloperGuide/index.html?using-query-api.html

    # sign the request (remember this is SignatureVersion '2')
    my $str_to_sign = '';
    $str_to_sign .= uc($self->verb) . "\n";
    $str_to_sign .= $self->host . "\n";
    $str_to_sign .= "/\n";

    my $param = $self->params();
    $str_to_sign .= join('&', map { "$_=" . uri_escape($param->{$_}) } sort keys %$param);

    # sign the $str_to_sign
    my $signature = ( $self->signature_method eq 'HmacSHA1' )
        ? hmac_sha1_base64($str_to_sign, $self->secret_access_key )
        : hmac_sha256_base64($str_to_sign, $self->secret_access_key );
    $self->set_param( 'Signature', $signature . '=' );
}

sub decode {
    my ($self) = @_;

    $self->data( XMLin( $self->res->content() ));
}

## ----------------------------------------------------------------------------
# all our lovely commands

sub describe_availability_zones {
    my ($self, $param) = @_;

    $self->set_command( 'DescribeAvailabilityZones' );
    return $self->send();
}

sub describe_regions {
    my ($self, $param) = @_;

    $self->set_command( 'DescribeRegions' );
    return $self->send();
}

sub allocate_address {
    my ($self, $param) = @_;

    $self->set_command( 'AllocateAddress' );
    return $self->send();
}

sub describe_addresses {
    my ($self, $param) = @_;

    $self->set_command( 'DescribeAddresses' );
    $self->send();

    # manipulate the addressesSet list we got back
    my $data = $self->data;
    $data->{addressesSet} = $self->_make_array( $data->{addressesSet}{item} );
    $self->data( $data );
    return $self->data;
}

sub release_address {
    my ($self, $param) = @_;

    unless ( defined $param->{PublicIp} ) {
        croak "Provide a 'PublicIp' address to release";
    }

    $self->set_command( 'ReleaseAddress' );
    $self->set_param( 'PublicIp', $param->{PublicIp} );
    return $self->send();
}

sub create_security_group {
    my ($self, $param) = @_;

    unless ( $self->is_valid_something($param->{GroupName}) ) {
        croak "Provide a 'GroupName' for the new security group";
    }

    unless ( $self->is_valid_something($param->{GroupDescription}) ) {
        croak "Provide a 'GroupDescription' for the new security group";
    }

    $self->set_command( 'CreateSecurityGroup' );
    $self->set_param( 'GroupName', $param->{GroupName} );
    $self->set_param( 'GroupDescription', $param->{GroupDescription} );
    return $self->send();
}

sub delete_security_group {
    my ($self, $param) = @_;

    unless ( $self->is_valid_something($param->{GroupName}) ) {
        croak "Provide a 'GroupName' to be deleted";
    }

    $self->set_command( 'DeleteSecurityGroup' );
    $self->set_param( 'GroupName', $param->{GroupName} );
    return $self->send();
}

sub describe_security_groups {
    my ($self, $param) = @_;

    $self->set_command( 'DescribeSecurityGroups' );
    $self->send();

    # manipulate the securityGroupInfo list we got back
    my $data = $self->data;
    $data->{securityGroupInfo} = $self->_make_array( $data->{securityGroupInfo}{item} );
    $self->data( $data );

    # flatten {ipPermissions}
    foreach my $info ( @{$data->{securityGroupInfo}} ) {
        $info->{ipPermissions} = $self->_make_array( $info->{ipPermissions}{item} );
        # flatten {groups} and {ipRanges}
        foreach my $ip ( @{$info->{ipPermissions}} ) {
            $ip->{groups} = $self->_make_array( $ip->{groups}{item} );
            $ip->{ipRanges} = $self->_make_array( $ip->{ipRanges}{item} );
        }
    }

    return $self->data;

}

## ----------------------------------------------------------------------------
# internal methods

sub _make_array {
    my ($self, $from) = @_;

    # return an empty list if not defined
    return [] unless defined $from;

    # return as-is if already an array
    return $from if ref $from eq 'ARRAY';

    # if this is a HASH, firstly check if there is anything in there
    if ( ref $from eq 'HASH' ) {
        # if nothing there, return an empty array
        return [] unless %$from;

        # just return the hash as the first element of an array
        return [ $from ];
    }

    # we probably have a scalar, so just return it as the first element of an array
    return [ $from ];
}

## ----------------------------------------------------------------------------
1;
## ----------------------------------------------------------------------------

=pod

=head1 NAME

AwsSum::Amazon::EC2 - interface to Amazon's EC2 web service

=head1 SYNOPSIS

    $ec2 = AwsSum::Amazon::EC2->new();
    $ec2->access_key_id( 'abc' );
    $ec2->secret_access_key( 'xyz' );

    # reserve an IP address
    $ec2->allocate_address();

    # list IP addresses
    $ec2->describe_addresses();

    # release an IP
    $ec2->release_address({ PublicIp => '1.2.3.4' });

=cut