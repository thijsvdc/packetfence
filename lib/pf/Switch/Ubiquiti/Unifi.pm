package pf::Switch::Ubiquiti::Unifi;

=head1 NAME

pf::Switch::Ubiquiti::Unifi

=head1 SYNOPSIS

The pf::Switch::Ubiquiti::Unifi module implements an object oriented interface to
manage Unifi  controllers

=head1 STATUS

Developed and tested on Unifi controller version 5.4.14 with a UniFi AP-AC-Pro running 3.4.14.3413

=head1 BUGS AND LIMITATIONS

=cut

use strict;
use warnings;

use base ('pf::Switch');

use DateTime;
use DateTime::Format::MySQL;
use pf::security_event qw(security_event_count_reevaluate_access);
use pf::constants::node qw($STATUS_UNREGISTERED);
use pf::file_paths qw($var_dir);
use pf::constants;
use pf::util;
use pf::node;
use pf::util::radius qw(perform_disconnect);
use pf::config qw(
    %connection_type_to_str
    $MAC
    $SSID
    $WEBAUTH_WIRELESS
);
use pf::locationlog;
use Try::Tiny;
use JSON::MaybeXS;

# The port to reach the Unifi controller API
our $UNIFI_API_PORT = "8443";

sub description { 'Unifi Controller' }

=head1 SUBROUTINES

=cut

# CAPABILITIES
# access technology supported
use pf::SwitchSupports qw(
    ExternalPortal
    WirelessDot1x
    WirelessMacAuth
);
# inline capabilities
sub inlineCapabilities { return ($MAC,$SSID); }

=head2 getVersion

Obtain image version information from switch

=cut

sub getVersion {
    my ($self)       = @_;
    my $oid_sysDescr = '1.3.6.1.2.1.1.1.0';
    my $logger       = $self->logger;
    if ( !$self->connectRead() ) {
        return '';
    }
    $logger->trace("SNMP get_request for sysDescr: $oid_sysDescr");
    my $result = $self->{_sessionRead}->get_request( -varbindlist => [$oid_sysDescr] );
    my $sysDescr = ( $result->{$oid_sysDescr} || '' );
    if ( $sysDescr =~ m/V(\d{1}\.\d{2}\.\d{2})/ ) {
        return $1;
    } elsif ( $sysDescr =~ m/Version (\d+\.\d+\([^)]+\)[^,\s]*)(,|\s)+/ ) {
        return $1;
    } else {
        return $sysDescr;
    }
}

=head2 synchronize_locationlog

Override the Switch method so that the controller IP is inserted as the switch_ip in the locationlog

=cut

sub synchronize_locationlog {
    my ( $self, $ifIndex, $vlan, $mac, $voip_status, $connection_type, $connection_sub_type, $user_name, $ssid, $stripped_user_name, $realm, $role, $ifDesc) = @_;
    # Set the switch IP to the controller IP so that the locationlog entry has the proper switch_ip entry
    $self->{_ip} = $self->returnSwitchIP($self->{_switchMac});
    $self->SUPER::synchronize_locationlog($ifIndex, $vlan, $mac, $voip_status, $connection_type, $connection_sub_type, $user_name, $ssid, $stripped_user_name, $realm, $role, $ifDesc);
}

=head2 returnSwitchIP

return the SwitchIP

=cut

sub returnSwitchIP {
    my ($self, $mac) = @_;
    if (my $ip = $self->getMACIP($mac)) {
        return $ip;
    }
    return $self->{_controllerIp};
}

=head2 parseExternalPortalRequest

Parse external portal request using URI and it's parameters then return an hash reference with the appropriate parameters

See L<pf::web::externalportal::handle>

=cut

sub parseExternalPortalRequest {
    my ( $self, $r, $req ) = @_;
    my $logger = $self->logger;

    # Using a hash to contain external portal parameters
    my %params = ();

    my $client_ip = defined($r->headers_in->{'X-Forwarded-For'}) ? $r->headers_in->{'X-Forwarded-For'} : $r->connection->remote_ip;

    %params = (
        switch_id               => $req->param('ap'),
        switch_mac              => $req->param('ap'),
        switch_ip               => $self->returnSwitchIP($req->param('ap')),
        client_mac              => clean_mac($req->param('id')),
        client_ip               => $client_ip,
        ssid                    => $req->param('ssid'),
        redirect_url            => $req->param('url'),
        status_code             => '200',
        synchronize_locationlog => $TRUE,
        connection_type         => $WEBAUTH_WIRELESS,
    );

    return \%params;
}

=head2 deauthTechniques

Return the reference to the deauth technique or the default deauth technique.

=cut

sub deauthTechniques {
    my ($self, $method, $connection_type) = @_;
    my $logger = $self->logger;
    my $default = $SNMP::HTTP;
    my %tech = (
        $SNMP::HTTP  => '_deauthenticateMacWithHTTP',
        $SNMP::RADIUS => 'deauthenticateMacRadius',
    );

    if ($connection_type == $WEBAUTH_WIRELESS) {
        $method = $SNMP::HTTP;
    }
    if (!defined($method) || !defined($tech{$method})) {
        $method = $default;
    }
    return $method,$tech{$method};
}

=head2 _connect

Return the connection to the controller

=cut

sub _connect {
    my ($self) = @_;
    my $logger = $self->logger;

    my $controllerIp = $self->{_controllerIp};
    my $transport = lc($self->{_wsTransport});
    my $username = $self->{_wsUser};
    my $password = $self->{_wsPwd};

    my $ua = LWP::UserAgent->new();
    $ua->cookie_jar({ file => "$var_dir/run/.ubiquiti.cookies.txt" });
    $ua->ssl_opts(verify_hostname => 0);
    $ua->timeout(10);


    my $base_url = "$transport://$controllerIp:$UNIFI_API_PORT";

    my $response = $ua->post("$base_url/api/login", Content => '{"username":"'.$username.'", "password":"'.$password.'"}');

    unless($response->is_success) {
        $logger->error("Can't login on the Unifi controller: ".$response->status_line);
        die;
    }
    return ($ua, $base_url);
}


=head2 _deauthenticateMacWithHTTP

Enable or disable the access of a user (portal vs no portal) using an HTTP webservices call

=cut

sub _deauthenticateMacWithHTTP {
    my ( $self, $mac ) = @_;
    my $logger = $self->logger;

    my $node_info = node_view($mac);

    my %site_opts;
    my $found = $FALSE;

    my $args = {
        mac => $mac,
    };
    my $command;
    unless ($node_info->{status} eq $STATUS_UNREGISTERED || security_event_count_reevaluate_access($mac))  {
        $command = "authorize-guest";
        my $now = DateTime->now();
        $now->set_time_zone('local');
        
        my $unregdate = DateTime::Format::MySQL->parse_datetime($node_info->{unregdate});
        $unregdate->set_time_zone('local');
        
        $args->{minutes} = $now->delta_ms($unregdate)->in_units('minutes');
    } else {
        $command = "unauthorize-guest";
    }

    $command = "kick-sta" if ($node_info->{last_connection_type} ne $connection_type_to_str{$WEBAUTH_WIRELESS});
    
    $args->{cmd} = $command;

    my ($ua, $base_url)  = $self->_connect();

    my $response = $ua->get("$base_url/api/self/sites");

    unless($response->is_success) {
        $logger->error("Can't have the site list from the Unifi controller: ".$response->status_line);
        return;
    }

    my $json_data = decode_json($response->decoded_content());

    $args->{ap_mac} = $self->{_id};
    foreach my $entry (@{$json_data->{'data'}}) {
        $response = $ua->get("$base_url/api/s/$entry->{'name'}/stat/sta/$mac");
        if ($response->is_success) {
            $found = $TRUE;
            $site_opts{'name'} = $entry->{'name'};
            $site_opts{'desc'} = $entry->{'desc'};
            $logger->info("Found site: $site_opts{'desc'}");
            last;
        }
    }

    if ($found) {
        $response = $ua->post("$base_url/api/s/$site_opts{'name'}/cmd/stamgr", Content => encode_json($args));
        if ($response->is_success) {
            $logger->info("Deauth on site: $site_opts{'desc'}");
        }
    } else {
        foreach my $entry (@{$json_data->{'data'}}) {
            $response = $ua->post("$base_url/api/s/$entry->{'name'}/cmd/stamgr", Content => encode_json($args));
            if ($response->is_success) {
                $logger->info("Deauth on site: $entry->{'desc'}");
            }
        }
    }

    unless($response->is_success) {
        $logger->error("Can't send request on the Unifi controller: ".$response->status_line);
        return;
    }

    $logger->info("Switched status on the Unifi controller using command $command");
}

=item getMACIP

get IP associated to a AP MAC

=cut


sub getMACIP {
    my ($self, $mac) = @_;
    my $logger = $self->logger;

    my $cache = $self->cache_distributed;

    my $result = $cache->get("Ubiquiti-" .$mac);

    return $result if defined($result);

    return $FALSE;
}

=item populateMACIP

Fetch all the AP on the controller and cache it

=cut


sub populateMACIP {
    my ($self) = @_;
    my $logger = $self->logger;

    my $cache = $self->cache_distributed;

    my $controllerIp = $self->{_controllerIp};
    my $transport = lc($self->{_wsTransport});
    my $username = $self->{_wsUser};
    my $password = $self->{_wsPwd};

    my ($ua, $base_url)  = $self->_connect();

    my $response = $ua->get("$base_url/api/self/sites");

    unless($response->is_success) {
        $logger->error("Can't have the site list from the Unifi controller: ".$response->status_line);
        return;
    }

    $response = $ua->get("$base_url/api/self/sites");

    my $json_data = decode_json($response->decoded_content());

    foreach my $entry (@{$json_data->{'data'}}) {
        $response = $ua->get("$base_url/api/s/$entry->{'name'}/stat/device/");
        unless($response->is_success) {
            $logger->error("Can't have the site list from the Unifi controller: ".$response->status_line);
            return;
        }
        my $json_data_ap = decode_json($response->decoded_content());
        foreach my $AP (@{$json_data_ap->{'data'}}) {
            $cache->compute("Ubiquiti-" . $AP->{'mac'} , sub { return $AP->{'ip'} } );
        }
    }
}


=item deauthenticateMacDefault

De-authenticate a MAC address from wireless network (including 802.1x).
New implementation using RADIUS Disconnect-Request.

=cut

sub deauthenticateMacRadius {
    my ( $self, $mac, $is_dot1x ) = @_;
    my $logger = $self->logger;

    if ( !$self->isProductionMode() ) {
        $logger->info("not in production mode... we won't perform deauthentication");
        return 1;
    }

    $logger->debug("deauthenticate $mac using RADIUS Disconnect-Request deauth method");
    return $self->radiusDisconnect($mac);
}

=item radiusDisconnect

Sends a RADIUS Disconnect-Request to the NAS with the MAC as the Calling-Station-Id to disconnect.
Optionally you can provide other attributes as an hashref.
Uses L<pf::util::radius> for the low-level RADIUS stuff.

=cut

# TODO consider whether we should handle retries or not?
sub radiusDisconnect {
    my ($self, $mac, $add_attributes_ref) = @_;
    my $logger = $self->logger;

    # initialize
    $add_attributes_ref = {} if (!defined($add_attributes_ref));

    if (!defined($self->{'_radiusSecret'})) {
        $logger->warn(
            "Unable to perform RADIUS Disconnect-Request on $self->{'_ip'}: RADIUS Shared Secret not configured"
        );
        return;
    }

    $logger->info("deauthenticating $mac");

    # Where should we send the RADIUS Disconnect-Request?
    # to network device by default
    my $send_disconnect_to = $self->{'_ip'};

    # allowing client code to override where we connect with NAS-IP-Address
    $send_disconnect_to = $add_attributes_ref->{'NAS-IP-Address'}
        if (defined($add_attributes_ref->{'NAS-IP-Address'}));

    my $response;
    try {
        my $locationlog = locationlog_view_open_mac($mac);
        my $connection_info = {
            nas_ip => $send_disconnect_to,
            secret => $self->{'_radiusSecret'},
            LocalAddr => $self->deauth_source_ip($send_disconnect_to),
        };

        # transforming MAC to the expected format 00-11-22-33-CA-FE
        $mac = uc($mac);
        $mac =~ s/:/-/g;
        my $nasID = $locationlog->{'switch_mac'};
        $nasID =~ s/://g;
        # Standard Attributes
        my $attributes_ref = {
            'Calling-Station-Id' => $mac,
            'NAS-Identifier' => $nasID,
        };

        # merging additional attributes provided by caller to the standard attributes
        $attributes_ref = { %$attributes_ref, %$add_attributes_ref };

        $response = perform_disconnect($connection_info, $attributes_ref);
    } catch {
        chomp;
        $logger->warn("Unable to perform RADIUS Disconnect-Request: $_");
        $logger->error("Wrong RADIUS secret or unreachable network device...") if ($_ =~ /^Timeout/);
    };
    return if (!defined($response));

    return $TRUE if ( ($response->{'Code'} eq 'Disconnect-ACK') || ($response->{'Code'} eq 'CoA-ACK') );

    $logger->warn(
        "Unable to perform RADIUS Disconnect-Request."
        . ( defined($response->{'Code'}) ? " $response->{'Code'}" : 'no RADIUS code' ) . ' received'
        . ( defined($response->{'Error-Cause'}) ? " with Error-Cause: $response->{'Error-Cause'}." : '' )
    );
    return;
}


=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2020 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;

# vim: set shiftwidth=4:
# vim: set expandtab:
# vim: set backspace=indent,eol,start:
