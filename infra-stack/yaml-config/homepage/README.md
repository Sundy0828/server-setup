# Homepage Configuration

Place your Homepage configuration files here. These will be mounted into the Homepage container.

## Files:

- `services.yaml` - Define your service cards and links
- `settings.yaml` - Homepage appearance and layout settings
- `widgets.yaml` - System monitoring widgets
- `bookmarks.yaml` - External links and bookmarks

The config is referenced in infra-stack/compose.yml and mounted at `/app/config`.
