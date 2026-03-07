#!/bin/bash
set -euo pipefail

#curl --location 'http://127.0.0.1:4723/session/21747b39-74eb-4840-81bd-6b8c60a0571c/elements' \
#--header 'Content-Type: application/json' \
#--data '{
#    "using": "predicate string",
#    "value": "description CONTAINS '\''Model inited'\''"
#}'

curl --location 'http://127.0.0.1:4723/session/bd083d5e-cd69-4b8d-9513-70305ab1a15b/elements' \
--header 'Content-Type: application/json' \
--data '{"using":"accessibility id","value":"browse_page_add_folder_button"}'


 