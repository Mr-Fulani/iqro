from django.contrib.postgres.operations import CreateExtension
from django.db import migrations


class Migration(migrations.Migration):
    """Per-query statistics for production tuning.

    The server loads the module via shared_preload_libraries (compose.production.yaml);
    this creates the view in the application database. Skipped outside PostgreSQL.
    """

    operations = [CreateExtension("pg_stat_statements")]
