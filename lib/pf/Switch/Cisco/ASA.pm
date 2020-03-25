package pf::Switch::Cisco::ASA;
=head1 NAME

pf::Switch::Cisco::ASA - Object oriented module

=head1 STATUS

Developed and tested on Cisco Adaptive Security Appliance Software Version 9.10(1) with Anyconnect 4.6.03049.

=over

=item Supports

=over

=item CoA

=back

=back

=head1 BUGS AND LIMITATIONS

=over

=back

=cut

use strict;
use warnings;

use Net::SNMP;
use Try::Tiny;

use base ('pf::Switch::Cisco');

use pf::constants;
use pf::config qw(
    $MAC
    $VIRTUAL_VPN
);
use pf::web::util;
use pf::util;
use pf::node;
use pf::util::radius qw(perform_coa);
use pf::radius::constants;
use pf::locationlog qw(locationlog_get_session);

sub description { 'Cisco ASA Firewall' }

=head1 SUBROUTINES

=over

=cut

# CAPABILITIES
# access technology supported
use pf::SwitchSupports qw(
    RadiusDynamicVlanAssignment
    AccessListBasedEnforcement
    ExternalPortal
    RoleBasedEnforcement
    VPN
);

=item identifyConnectionType

Determine Connection Type based on radius attributes

=cut

sub identifyConnectionType {
    my ( $self, $connection, $radius_request ) = @_;

    my @require = qw(ASA-TunnelGroupName);
    my @found = grep {exists $radius_request->{$_}} @require;
    if (@require == @found) {
        $connection->isVPN($TRUE);
        $connection->isCLI($FALSE);
    } else {
        $connection->isVPN($FALSE);
    }
}


=item deauthenticateMacDefault

Send a CoA to change the attributes on the fly.

=cut

sub deauthenticateMacDefault {
    my ( $self, $mac, $is_dot1x ) = @_;
    my $logger = $self->logger;

    if ( !$self->isProductionMode() ) {
        $logger->info("not in production mode... we won't perform deauthentication");
        return 1;
    }

    $logger->debug("Change the state of $mac using RADIUS CoA");
    return $self->radiusDisconnect( $mac, { 'Service-Type' => 'Login-User'} );
}

=item deauthTechniques

Return the reference to the deauth technique or the default deauth technique.

=cut

sub deauthTechniques {
    my ($self, $method, $connection_type) = @_;
    my $logger = $self->logger;
    my $default = $SNMP::RADIUS;
    my %tech = (
        $SNMP::RADIUS => 'deauthenticateMacDefault',
    );

    if (!defined($method) || !defined($tech{$method})) {
        $method = $default;
    }
    return $method,$tech{$method};
}

=item returnAuthorizeVPN

Return radius attributes to allow VPN access

=cut

sub returnAuthorizeVPN {
    my ($self, $args) = @_;
    my $logger = $self->logger;

    $args->{'unfiltered'} = $TRUE;
    my @super_reply = @{$self->SUPER::returnRadiusAccessAccept($args)};
    my $status = shift @super_reply;
    my %radius_reply = @super_reply;
    my $radius_reply_ref = \%radius_reply;
    return [$status, %$radius_reply_ref] if($status == $RADIUS::RLM_MODULE_USERLOCK);

    my @av_pairs = defined($radius_reply_ref->{'Cisco-AVPair'}) ? @{$radius_reply_ref->{'Cisco-AVPair'}} : ();

    if (isenabled($self->{_VlanMap}) && $self->supportsRadiusDynamicVlanAssignment ) {
        if( defined($args->{'user_role'}) && $args->{'user_role'} ne "" && defined($self->getVlanByName($args->{'user_role'}))) {
            my $vlan = $self->getVlanByName($args->{'user_role'});
            $args->{'vlan'} = $vlan;
            my $vlanpool = new pf::role::pool;
            $vlan = $vlanpool->getVlanFromPool($args);
            push(@av_pairs, "Tunnel-Medium-Type=$RADIUS::ETHERNET;Tunnel-Type=$RADIUS::VLAN;Tunnel-Private-Group-ID=$vlan");
            delete $radius_reply_ref->{'Tunnel-Medium-Type'};
            delete $radius_reply_ref->{'Tunnel-Type'};
            delete $radius_reply_ref->{'Tunnel-Type'};
        }
    }
    if ( isenabled($self->{_RoleMap}) && $self->supportsRoleBasedEnforcement()) {
        if ( !defined($self->getUrlByName($args->{'user_role'}) ) ) {
            $logger->debug("Network device (".$self->{'_id'}.") supports roles. Evaluating role to be returned");
            my $role;
            if ( defined($args->{'user_role'}) && $args->{'user_role'} ne "" ) {
                $role = $self->getRoleByName($args->{'user_role'});
            }
            if ( defined($role) && $role ne "" ) {
                push(@av_pairs, $self->returnRoleAttribute."=".$self->returnRoleAttributes($role));
                $logger->info(
                    "(".$self->{'_id'}.") Added role $role to the returned RADIUS Access-Accept"
                );
                delete $radius_reply_ref->{$self->returnRoleAttribute};
            }
            else {
                $logger->debug("(".$self->{'_id'}.") Received undefined role. No Role added to RADIUS Access-Accept");
            }
        }
    }
    if ( isenabled($self->{_AccessListMap}) && $self->supportsAccessListBasedEnforcement ){
        if( defined($args->{'user_role'}) && $args->{'user_role'} ne "" && defined($self->getAccessListByName($args->{'user_role'}))){
            my $access_list = $self->getAccessListByName($args->{'user_role'});
            if ($access_list) {
                my $acl_num = 101;
                while($access_list =~ /([^\n]+)\n?/g){
                    push(@av_pairs, $self->returnAccessListAttribute($acl_num)."=".$1);
                    $acl_num ++;
                    $logger->info("(".$self->{'_id'}.") Adding access list : $1 to the RADIUS reply");
                }
                $logger->info("(".$self->{'_id'}.") Added access lists to the RADIUS reply.");
            } else {
                $logger->info("(".$self->{'_id'}.") No access lists defined for this role ".$args->{'user_role'});
            }
        }
    }

    my $role = $self->getRoleByName($args->{'user_role'});
    if ( isenabled($self->{_UrlMap}) && $self->externalPortalEnforcement ) {
        if ( defined($args->{'user_role'}) && $args->{'user_role'} ne "" && defined($self->getUrlByName($args->{'user_role'}) ) ) {
            $args->{'session_id'} = "sid".$self->setSession($args);
            my $redirect_url = $self->getUrlByName($args->{'user_role'});
            $redirect_url .= '/' unless $redirect_url =~ m(\/$);
            $redirect_url .= $args->{'session_id'};
            $redirect_url .= "?";
            #override role if a role in role map is define
            if (isenabled($self->{_RoleMap}) && $self->supportsRoleBasedEnforcement()) {
                my $role_map = $self->getRoleByName($args->{'user_role'});
                $role = $role_map if (defined($role_map));
                # remove the role if any as we push the redirection ACL along with it's role
                delete $radius_reply_ref->{$self->returnRoleAttribute()};
            }
            $logger->info("Adding web authentication redirection to reply using role: '$role' and URL: '$redirect_url'");
            push @av_pairs, "url-redirect-acl=$role";
            push @av_pairs, "url-redirect=".$redirect_url;
        }
    }

    $radius_reply_ref->{'Cisco-AVPair'} = \@av_pairs;

    my $filter = pf::access_filter::radius->new;
    my $rule = $filter->test('returnRadiusAccessAccept', $args);
    ($radius_reply_ref, $status) = $filter->handleAnswerInRule($rule,$args,$radius_reply_ref);
    return [$status, %$radius_reply_ref];
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
    $mac = clean_mac($mac);
    $add_attributes_ref = {} if (!defined($add_attributes_ref));

    if (!defined($self->{'_radiusSecret'})) {
        $logger->warn(
            "Unable to perform RADIUS CoA-Request on (".$self->{'_id'}."): RADIUS Shared Secret not configured"
        );
        return;
    }

    $logger->info("Sending CoA");

    # Where should we send the RADIUS CoA-Request?
    # to network device by default
    my $send_disconnect_to = $self->{'_ip'};
    # but if controllerIp is set, we send there
    if (defined($self->{'_controllerIp'}) && $self->{'_controllerIp'} ne '') {
        $logger->info("controllerIp is set, we will use controller $self->{_controllerIp} to perform deauth");
        $send_disconnect_to = $self->{'_controllerIp'};
    }
    # On which port we have to send the CoA-Request ?
    my $nas_port = $self->{'_disconnectPort'} || '3799';
    my $coa_port = $self->{'_coaPort'} || '1700';
    # allowing client code to override where we connect with NAS-IP-Address
    $send_disconnect_to = $add_attributes_ref->{'NAS-IP-Address'}
        if (defined($add_attributes_ref->{'NAS-IP-Address'}));

    my $response;
    try {
        my $connection_info = {
            nas_ip => $send_disconnect_to,
            secret => $self->{'_radiusSecret'},
            LocalAddr => $self->deauth_source_ip($send_disconnect_to),
            nas_port => $coa_port,
        };

        $logger->debug("network device (".$self->{'_id'}.") supports roles. Evaluating role to be returned");
        my $roleResolver = pf::roles::custom->instance();
        my $role;

        my $node_info = node_view($mac);

        if ($node_info->{status} eq 'unreg') {
            $role = 'registration';
        } else {
            $role = $node_info->{category};
        }

        my $args = {
           mac => $mac,
           user_role => $role,
           node_info => $node_info,
        };

        $args->{'unfiltered'} = $TRUE;
        my @super_reply = @{$self->returnAuthorizeVPN($args)};
        my $status = shift @super_reply;
        my %radius_reply = @super_reply;
        my $radius_reply_ref = \%radius_reply;

        my @vsa;
        if (defined($radius_reply_ref->{'Cisco-AVPair'})) {
            foreach my $avpair (@{$radius_reply_ref->{'Cisco-AVPair'}}) {
                my $coa_attributes = {vendor => "Cisco",attribute => "Cisco-AVPair",value => $avpair };
                push @vsa, $coa_attributes;
            }
        }
        push @vsa, {vendor => "Cisco",attribute => "Cisco-AVPair",value => "audit-session-id=$node_info->{'sessionid'}" };
        my $vsa = \@vsa;

        # transforming MAC to the expected format 00-11-22-33-CA-FE
        $mac = uc($mac);
        $mac =~ s/:/-/g;
        # Standard Attributes

        my $attributes_ref = {
            'Calling-Station-Id' => $mac,
            'NAS-IP-Address' => $send_disconnect_to,
            'NAS-Port' => $node_info->{'last_port'},
        };

        # merging additional attributes provided by caller to the standard attributes
        $attributes_ref = { %$attributes_ref, %$add_attributes_ref };

        # Roles are configured and the user should have one.
        # We send a regular disconnect if there is an open trapping security_event
        # to ensure the VLAN is actually changed to the isolation VLAN.
        $logger->info("Returning ACCEPT with Role: $role");

        $response = perform_coa($connection_info, $attributes_ref, $vsa);
    } catch {
        chomp;
        $logger->warn("Unable to perform RADIUS CoA-Request on (".$self->{'_id'}."): $_");
        $logger->error("Wrong RADIUS secret or unreachable network device (".$self->{'_id'}.")... On some Cisco Wireless Controllers you might have to set disconnectPort=1700 as some versions ignore the CoA requests on port 3799") if ($_ =~ /^Timeout/);
    };
    return if (!defined($response));

    return $TRUE if ( ($response->{'Code'} eq 'Disconnect-ACK') || ($response->{'Code'} eq 'CoA-ACK') );

    $logger->warn(
        "Unable to perform RADIUS Disconnect-Request on (".$self->{'_id'}.")."
        . ( defined($response->{'Code'}) ? " $response->{'Code'}" : 'no RADIUS code' ) . ' received'
        . ( defined($response->{'Error-Cause'}) ? " with Error-Cause: $response->{'Error-Cause'}." : '' )
    );
    return;
}

=item parseVPNRequest

Redefinition of pf::Switch::parseVPNRequest due to specific attribute being used

=cut

sub parseVPNRequest {
    my ( $self, $radius_request ) = @_;
    my $logger = $self->logger;

    my $client_mac;
    my $client_ip       = ref($radius_request->{'Calling-Station-Id'}) eq 'ARRAY'
                           ? clean_ip($radius_request->{'Calling-Station-Id'}[0])
                           : clean_ip($radius_request->{'Calling-Station-Id'});

    my $user_name       = $self->parseRequestUsername($radius_request);
    my $nas_port_type   = $radius_request->{'NAS-Port-Type'};
    my $port            = $radius_request->{'NAS-Port'};
    my $eap_type        = ( exists($radius_request->{'EAP-Type'}) ? $radius_request->{'EAP-Type'} : 0 );
    my $nas_port_id     = ( defined($radius_request->{'NAS-Port-Id'}) ? $radius_request->{'NAS-Port-Id'} : undef );

    my $session_id;
    if (defined($radius_request->{'Cisco-AVPair'})) {
        foreach my $avpair (@{$radius_request->{'Cisco-AVPair'}}) {
            if ($avpair =~ /audit-session-id=(.*)/ig ) {
                $session_id = $1;
            }
            if ($avpair =~ /mdm-tlv=device-mac=(.*)/ig ) {
                $client_mac = clean_mac($1);
            }
        }
    }
    return ($nas_port_type, $eap_type, $client_mac, $port, $user_name, $nas_port_id, $session_id, $nas_port_id);
}

=item parseExternalPortalRequest

Parse external portal request using URI and its parameters then return a hash reference with the appropriate parameters

See L<pf::web::externalportal::handle>

=cut

sub parseExternalPortalRequest {
    my ( $self, $r, $req ) = @_;
    my $logger = $self->logger;

    # Using a hash to contain external portal parameters
    my %params = ();

    # Cisco ASA uses external portal session ID handling process
    my $uri = $r->uri;
    return unless ($uri =~ /.*sid(\w+[^\/\&])/);
    my $session_id = $1;

    my $locationlog = pf::locationlog::locationlog_get_session($session_id);

    my $switch_id = $locationlog->{switch};
    my $client_mac = $locationlog->{mac};
    my $client_ip = defined($r->headers_in->{'X-Forwarded-For'}) ? $r->headers_in->{'X-Forwarded-For'} : $r->connection->remote_ip;

    my $redirect_url = '';
    if ( defined($req->param('redirect')) ) {
        $redirect_url = $req->param('redirect');
    }
    elsif ( defined($req->param('redirect_url')) ) {
        $redirect_url = $req->param('redirect_url');
    }
    elsif ( defined($r->headers_in->{'Referer'}) ) {
        $redirect_url = $r->headers_in->{'Referer'};
    }

    if($redirect_url ne '' && $redirect_url !~ /^http/) {
        $redirect_url = "http://".$redirect_url;
    }

    %params = (
        session_id              => $session_id,
        switch_id               => $switch_id,
        client_mac              => $client_mac,
        client_ip               => $client_ip,
        redirect_url            => $redirect_url || '',
        synchronize_locationlog => $FALSE,
        connection_type         => $VIRTUAL_VPN,
    );
    return \%params;
}


=head2 returnAccessListAttribute

Returns the attribute to use when pushing an ACL using RADIUS

=cut

sub returnAccessListAttribute {
    my ($self, $acl_num) = @_;
    return "ip:inacl#$acl_num";
}

=head2 returnRoleAttribute

What RADIUS Attribute (usually VSA) should the role be returned into.

=cut

sub returnRoleAttribute {
    my ($self) = @_;

    return 'Filter-Id';
}

=back

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
