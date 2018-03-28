# Class: splunk
#
# This class deploys Splunk on Linux, Windows, Solaris platforms.
#
# Parameters:
#
# [*package_source*]
#   The source URL for the splunk installation media (typically an RPM, MSI,
#   etc). If a $src_root parameter is set in splunk::params, this will be
#   automatically supplied. Otherwise it is required. The URL can be of any
#   protocol supported by the puppet/archive module. On Windows, this can
#   be a UNC path to the MSI.
#
# [*package_name*]
#   The name of the package(s) as they will exist or be detected on the host.
#
# [*package_ensure]
#   ensurance of the package
#
# [*logging_port*]
#   The port to recieve splunktcp logs on.
#
# [*splunkd_port*]
#   The splunkd port. Used as a default for both splunk and splunk::forwarder.
#
# [*splunkd_listen*]
#   The address on which splunkd should listen. Defaults to localhost only.
#
# [*web_port*]
#   The port on which to serve the Splunk Web interface.
#
# [*purge_inputs*]
#   If set to true, will remove any inputs.conf configuration not supplied by
#   Puppet from the target system. Defaults to false.
#
# [*purge_outputs*]
#   If set to true, will remove any outputs.conf configuration not supplied by
#   Puppet from the target system. Defaults to false.
#
# Actions:
#
#   Declares parameters to be consumed by other classes in the splunk module.
#
# Requires: nothing
#
class splunk (
  $package_source         = $splunk::params::server_pkg_src,
  $package_name           = $splunk::params::server_pkg_name,
  $package_ensure         = $splunk::params::server_pkg_ensure,
  $server_service         = $splunk::params::server_service,
  $logging_port           = $splunk::params::logging_port,
  $splunkd_port           = $splunk::params::splunkd_port,
  $splunk_user            = $splunk::params::splunk_user,
  $pkg_provider           = $splunk::params::pkg_provider,
  $splunkd_listen         = '127.0.0.1',
  $web_port               = '8000',
  $purge_alert_actions    = false,
  $purge_authentication   = false,
  $purge_authorize        = false,
  $purge_deploymentclient = false,
  $purge_distsearch       = false,
  $purge_indexes          = false,
  $purge_inputs           = false,
  $purge_limits           = false,
  $purge_outputs          = false,
  $purge_props            = false,
  $purge_server           = false,
  $purge_serverclass      = false,
  $purge_transforms       = false,
  $purge_uiprefs          = false,
  $purge_web              = false,
) inherits splunk::params {

  $virtual_service = $server_service
  $staging_subdir  = $splunk::params::staging_subdir

  $path_delimiter  = $splunk::params::path_delimiter

  if $pkg_provider != undef and $pkg_provider != 'yum' and $pkg_provider != 'apt' and $pkg_provider != 'chocolatey' {
    include ::archive::staging
    $src_pkg_filename = basename($package_source)
    $pkg_path_parts   = [$archive::path, $staging_subdir, $src_pkg_filename]
    $staged_package   = join($pkg_path_parts, $path_delimiter)

    archive { $staged_package:
      source  => $package_source,
      extract => false,
      before  => Package[$package_name],
    }
  } else {
    $staged_package = undef
  }

  Package {
    source   => $pkg_provider ? {
      'chocolatey' => undef,
      default      => pick($staged_package, $package_source),
    },
  }

  package { $package_name:
    ensure   => $package_ensure,
    provider => $pkg_provider,
    before   => Service[$virtual_service],
    tag      => 'splunk_server',
  }

  if $facts['virtual'] == 'docker' {
    ini_setting { 'OPTIMISTIC_ABOUT_FILE_LOCKING':
      ensure  => present,
      section => '',
      setting => 'OPTIMISTIC_ABOUT_FILE_LOCKING',
      value   => '1',
      path    => '/opt/splunk/etc/splunk-launch.conf',
    }

    Package[$package_name]
    -> Ini_setting['OPTIMISTIC_ABOUT_FILE_LOCKING']
    -> Exec <| tag   == 'splunk_server'  |>
  }


  splunk_input { 'default_host':
    section => 'default',
    setting => 'host',
    value   => $::clientcert,
    tag     => 'splunk_server',
  }
  splunk_input { 'default_splunktcp':
    section => "splunktcp://:${logging_port}",
    setting => 'connection_host',
    value   => 'dns',
    tag     => 'splunk_server',
  }
  splunk_web { 'splunk_server_splunkd_port':
    section => 'settings',
    setting => 'mgmtHostPort',
    value   => "${splunkd_listen}:${splunkd_port}",
    tag     => 'splunk_server',
  }

  splunk_web { 'splunk_server_web_port':
    section => 'settings',
    setting => 'httpport',
    value   => $web_port,
    tag     => 'splunk_server',
  }


  # Purge resources if option set
  Splunk_config['splunk'] {
    purge_alert_actions  => $purge_alert_actions,
    purge_authentication   => $purge_authentication,
    purge_authorize        => $purge_authorize,
    purge_deploymentclient => $purge_deploymentclient,
    purge_distsearch       => $purge_distsearch,
    purge_indexes          => $purge_indexes,
    purge_inputs           => $purge_inputs,
    purge_limits           => $purge_limits,
    purge_outputs          => $purge_outputs,
    purge_props            => $purge_props,
    purge_server           => $purge_server,
    purge_serverclass      => $purge_serverclass,
    purge_transforms       => $purge_transforms,
    purge_uiprefs          => $purge_uiprefs,
    purge_web              => $purge_web
  }
  # This is a module that supports multiple platforms. For some platforms
  # there is non-generic configuration that needs to be declared in addition
  # to the agnostic resources declared here.
  case $::kernel {
    'Linux': {
      class { '::splunk::platform::posix':
        splunkd_port   => $splunkd_port,
        splunk_user    => $splunk_user,
        server_service => $server_service,
      }
    }
    'SunOS': { include ::splunk::platform::solaris }
    default: { } # no special configuration needed
  }

  # Realize resources shared between server and forwarder profiles, and set up
  # dependency chains.
  include ::splunk::virtual

  # This realize() call is because the collectors don't seem to work well with
  # arrays. They'll set the dependencies but not realize all Service resources
  realize(Service[$virtual_service])

  Package[$package_name]
  -> Exec <| tag   == 'splunk_server'  |>
  -> File <| tag   == 'splunk_server'  |>
  -> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_alert_actions   <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_authentication  <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_authorize       <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                    <| tag   == 'splunk_server'  |>
  -> Splunk_deploymentclient <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_distsearch      <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_indexes         <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_input           <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_limits          <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_output          <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_props           <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_server          <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_serverclass     <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_transforms      <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_uiprefs         <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  Package[$package_name]
  -> File                   <| tag   == 'splunk_server'  |>
  -> Splunk_web             <| tag   == 'splunk_server'  |>
  ~> Service[$virtual_service]

  File {
    owner => $splunk_user,
    group => $splunk_user,
    mode => '0600',
  }

  file { '/opt/splunk/etc/system/local/alert_actions.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/authentication.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/authorize.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/deploymentclient.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/distsearch.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/indexes.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/inputs.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/limits.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/outputs.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/props.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/server.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/serverclass.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/transforms.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/ui-prefs.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  file { '/opt/splunk/etc/system/local/web.conf':
    ensure => file,
    tag    => 'splunk_server',
  }

  # Validate: if both Splunk and Splunk Universal Forwarder are installed on
  # the same system, then they must use different admin ports.
  if (defined(Class['splunk']) and defined(Class['splunk::forwarder'])) {
    $s_port = $splunk::splunkd_port
    $f_port = $splunk::forwarder::splunkd_port
    if $s_port == $f_port {
      fail(regsubst("Both splunk and splunk::forwarder are included, but both
        are configured to use the same splunkd port (${s_port}). Please either
        include only one of splunk, splunk::forwarder, or else configure them
        to use non-conflicting splunkd ports.", '\s\s+', ' ', 'G')
      )
    }
  }

}
