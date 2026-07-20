// Hand-authored Sonos config descriptor — the renderer-first fixture.
//
// Stands in for `GET /plugins/plugin.sonos/config/descriptor` until the SDK
// emits it (see plugin_config_descriptor.md phases). Exercises duration,
// list<host>, port, a required_when conditional, a note, an enum-as-segmented,
// a data-bound table, and a hidden secret group.

const Map<String, dynamic> sonosDescriptorFixture = {
  'plugin_id': 'plugin.sonos',
  'descriptor_version': 1,
  'title': 'Sonos',
  'sections': [
    {
      'id': 'discovery',
      'title': 'Discovery',
      'icon': 'radar',
      'fields': [
        {
          'key': 'sonos.discovery_interval_secs',
          'kind': 'duration',
          'unit': 'secs',
          'label': 'Discovery interval',
          'default': 60,
          'help': 'How often to re-run SSDP discovery.',
        },
        {
          'key': 'sonos.discovery_timeout_secs',
          'kind': 'duration',
          'unit': 'secs',
          'label': 'Scan duration',
          'default': 5,
          'help': 'How long each SSDP scan listens.',
        },
        {
          'key': 'sonos.manual_hosts',
          'kind': 'list',
          'item': 'host',
          'label': 'Manual hosts',
          'default': [],
          'help': 'Static speaker IPs to probe in addition to SSDP.',
        },
      ],
    },
    {
      'id': 'api',
      'title': 'HTTP API',
      'icon': 'api',
      'fields': [
        {
          'key': 'api.enabled',
          'kind': 'toggle',
          'label': 'Enable HTTP API',
          'default': true,
        },
        {
          'kind': 'note',
          'text':
              'A standalone web interface (independent of homeCore) for exploring each speaker — browse favorites and playlists, see now-playing and group state, and read diagnostics. Handy for content discovery and debugging.',
          'visible_when': {'field': 'api.enabled', 'truthy': true},
        },
        {
          'kind': 'link',
          'label': 'Open web interface',
          'help': 'Opens the Sonos HTTP API in a new tab.',
          'href': 'http://{client_host}:{api.port}/',
          'visible_when': {'field': 'api.enabled', 'truthy': true},
        },
        {
          'key': 'api.host',
          'kind': 'host',
          'label': 'Bind address',
          'default': '0.0.0.0',
          'visible_when': {'field': 'api.enabled', 'truthy': true},
        },
        {
          'key': 'api.port',
          'kind': 'port',
          'label': 'Port',
          'default': 5005,
          'visible_when': {'field': 'api.enabled', 'truthy': true},
        },
        {
          'key': 'api.callback_host',
          'kind': 'host',
          'label': 'Callback host',
          'help': 'The LAN IP speakers reach for GENA event callbacks.',
          'visible_when': {'field': 'api.enabled', 'truthy': true},
          'required_when': {
            'field': 'api.host',
            'in': ['0.0.0.0', '::'],
          },
        },
        {
          'kind': 'note',
          'text':
              'When the API binds all interfaces (0.0.0.0), speakers need a concrete LAN IP to deliver event callbacks — set Callback host to this machine\'s address.',
          'visible_when': {
            'field': 'api.host',
            'in': ['0.0.0.0', '::'],
          },
        },
      ],
    },
    {
      'id': 'speakers',
      'title': 'Speakers',
      'icon': 'speaker',
      'fields': [
        {
          'key': 'devices',
          'kind': 'table',
          'render': 'cards',
          'key_by': 'device_id',
          'label': 'Speakers',
          'default': [],
          'help':
              'Every discovered speaker — set its name and room. Overrides are pinned; the rest follow discovery.',
          'source': {
            'kind': 'core_resource',
            'ref': 'sonos_devices',
            'item_key': 'device_id',
            'labels': {'title': 'name', 'subtitle': 'device_id'},
          },
          'item': [
            {'key': 'name', 'kind': 'text', 'label': 'Name'},
            {
              'key': 'area',
              'kind': 'select',
              'label': 'Room',
              'placeholder': 'Unassigned',
              'allow_create': true,
              'source': {'kind': 'core_resource', 'ref': 'areas'},
            },
          ],
        },
      ],
    },
    {
      'id': 'logging',
      'title': 'Logging',
      'icon': 'list',
      'fields': [
        {
          'key': 'logging.level',
          'kind': 'text',
          'label': 'Level',
          'default': 'info',
          'placeholder': 'info | debug | hc_sonos=debug',
        },
        {
          'key': 'logging.log_forward_level',
          'kind': 'enum',
          'render': 'segmented',
          'label': 'Forward to core',
          'default': 'info',
          'options': [
            {'value': 'off', 'label': 'Off'},
            {'value': 'error', 'label': 'Error'},
            {'value': 'warn', 'label': 'Warn'},
            {'value': 'info', 'label': 'Info'},
            {'value': 'debug', 'label': 'Debug'},
          ],
        },
        {
          'key': 'logging.rotation',
          'kind': 'enum',
          'render': 'segmented',
          'label': 'Rotate',
          'default': 'daily',
          'options': [
            {'value': 'hourly', 'label': 'Hourly'},
            {'value': 'daily', 'label': 'Daily'},
            {'value': 'weekly', 'label': 'Weekly'},
            {'value': 'never', 'label': 'Never'},
          ],
        },
        {
          'key': 'logging.max_size_mb',
          'kind': 'int',
          'unit': 'MB',
          'label': 'Rotate at size',
          'default': 100,
          'min': 0,
        },
        {
          'key': 'logging.prune_after_days',
          'kind': 'int',
          'unit': 'days',
          'label': 'Prune after',
          'default': 0,
          'min': 0,
          'help': '0 = never prune.',
        },
        {
          'key': 'logging.compress',
          'kind': 'toggle',
          'label': 'Compress rotated files',
          'default': true,
        },
      ],
    },
    {
      'id': 'connection',
      'title': 'Connection',
      'hidden': true,
      'fields': [
        {'key': 'homecore.broker_host', 'kind': 'host', 'label': 'Broker host'},
        {'key': 'homecore.broker_port', 'kind': 'port', 'label': 'Broker port'},
        {
          'key': 'homecore.password',
          'kind': 'secret',
          'label': 'Broker password',
        },
      ],
    },
  ],
};
