## Puppet-related scripts

#### find_deprecated_template_vars.sh
I wrote this script to identify variable accesses in templates that Puppet 3 would complain about being deprecated. It looks for non-instance variable accesses that aren't defined within the template

#### check-indentation.py
This script ensures indentation consistency in puppet manifests. It looks for lines containing corresponding opening/closing curly braces to have the same indentation, and for content inside those curly braces to be indented further than the lines containining the opening/closing curly braces.

#### puppet-run.sh, puppet-pause.sh, and puppet-functions.sh
These scripts are helpful wrappers for running puppet.
