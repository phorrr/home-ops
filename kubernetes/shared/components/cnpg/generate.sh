# Set the application name
export APP=$1

# Generate a secure password
PASSWORD=$(op item create --category password --generate-password=letters,digits,20 --dry-run --format json | jq -r '.fields[0].value')

# Store credentials in 1Password
op item edit cloudnative-pg "${APP}_postgres_username[text]=${APP}"
op item edit cloudnative-pg "${APP}_postgres_password[password]=${PASSWORD}"
