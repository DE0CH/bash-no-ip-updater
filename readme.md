## Bash No-IP Updater

A bash script to update the IP address of [No-IP](https://www.noip.com/) hostnames. Supports multiple hostname updates (see `config_sample`). Interprets [No-IP protocol responses](https://www.noip.com/integrate/response) and follows client guidelines.

## Prerequisites

- `bash`
- `curl` or `wget`
- GNU `coreutils`

## Usage

`noipupdater.sh [-c /path/to/config] [-i 123.123.123.123]`

- `-c` (optional): Path to config file (see `config_sample`). If this parameter is not specified, then the script will look for file `config` in the same directory as the script.
- `-i` (optional): Manually set the IP address that should be assigned to the hostname(s). If this paremter is not specified, the IP address will be auto-detected by No-IP.

## Automation

Include the script in your cron file (`crontab -e`):

Run script once each day at 5:30am:  
`30 5 * * * /path/to/noipupdater.sh`

Run the script every fifteen minutes:  
`*/15 * * * * /path/to/noipupdater.sh`

### Notes

- This is a bash script, so you may need to specify `SHELL=/bin/bash` in crontab.
- `cron` is often configured to send mail when a command outputs to the console. Set configuration option `CONSOLE_OUTPUT_LEVEL` to silence non-error or all console outputs if you want to avoid this mail.

## Credits

Forked from the [Simple Bash No-IP Updater by AntonioCS](https://github.com/AntonioCS/no-ip.com-bash-updater)

2013 © Matthew D. Mower  
2012 © AntonioCS
