SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

source $SCRIPT_DIR/.auth-config

# Need to determine if AWS_CLI is installed to be successful

INPUT=$1
FORCE_SELECTION=$2

# This is the bitwarden ID of the login. Change this value to your ID.
passw=""
pw=""
totp=""
force_refresh=""

if [ -z $PROFILE ]
then
	echo "No profile name given. Using the default"
	PROFILE="default"
fi

print_help() {
	echo "======================================"
	echo "\tSecEng AWS Auth Script"
	echo "======================================"
	echo ""
	echo "Syntax: awscli-se-auth.sh [<command>]"
	echo ""
	echo "--- commands ---"
	echo "-lp | --list-profiles\n\t\tList the current profiles inside of ~/.okta-aws"
	echo "-h | --help\n\t\tPrint this help menu"
	echo "-f | --force\n\t\tForce the role selection for the current profile even if valid session"
	echo "profile=<profile_name>\n\t\tSet the name of the profile to be used."
}

prep_okta_file() {
	for label in "default" $PROFILE
	do
		grep -i "\[$label\]" ~/.okta-aws > /dev/null
		resp=$?
		if ! [[ -f ~/.okta-aws ]] || [[ $resp != 0 ]]
		then
			echo "~/.okta-aws does not exist. Creating..."
			echo "[$label]" >> ~/.okta-aws
			echo "base-url = veevasys.okta.com" >> ~/.okta-aws
			if [[ "$label" == "default" ]]
			then
				echo "app-link = https://veevasys.okta.com/home/amazon_aws/0oa1b9jgpxvFWCWwR0h8/272" >> ~/.okta-aws
			fi
			echo "duration = 43200" >> ~/.okta-aws
		fi
	done

}

prep_bw() {
	# Check if bitwarden exists
	if ! which $BW_PATH > /dev/null
	then
		echo "Error. Bitwarden CLI not found. Please refer to: https://bitwarden.com/help/cli/."
	else

		bw_server=$($BW_PATH config server)
		if [[ ! "$bw_server" == "$BW_URL" ]]
		then
			echo "This is where the URL should get set" 
		fi
		# using "bw config server" you get the current server definition. Need to check if accurate to variable
		# Steps
		# bw config server $BW_URL
		# bw login <email> --sso 
		# bw unlock $passw (prompt)
	fi
}

check_profile() {
	
	echo "Checking if profile $PROFILE exists in ~/.okta-aws"
	# Check if the sam-dev profile exists in okta-aws
	grep -i "\[$PROFILE\]" ~/.okta-aws > /dev/null
	resp=$?
	# If the grep fails 
	if [[ $resp != 0 ]]
	then
		echo "The profile $PROFILE was not found. Will create with role selection"
	fi
	
}

unlock_bitwarden_cli() {
	passw=""
	if [ $KEYSTORE = true ]
	then
		echo "Using the password unlock command..."
		passw=$($KEYSTORE_CMD)
	else
		read -s -p "Enter bitwarden password: " passw
	fi
	echo "Retrieveing login credentials for veevasys.okta.com from bitwarden..."
	session=$($BW_PATH unlock $passw | tail -n1 | awk -F "session " '{print $2}')
	EMAIL=$($BW_PATH get username $OKTA_BIT_ID --session $session)
	echo "Using email: $EMAIL"
	pw=$($BW_PATH get password $OKTA_BIT_ID --session $session)
	# Need to add logic to use this
	if [[ $BW_TOTP ]]
	then
		totp=$($BW_PATH get totp $OKTA_BIT_ID --session $session)
	fi
}

authenticate_aws() {
	echo "Logging into Okta SSO with email: $EMAIL"
	OKTA_CMD=""
	# Only include the TOTP flag if using BW generator
	if [ ! -z $totp ]
	then
		OKTA_CMD+="-t $totp "
	fi
	# Allow the user to force role selection for the current profile
	if [ ! -z $force_refresh ]
	then
		OKTA_CMD+="-f "
	fi
	okta-awscli -o $PROFILE -U $EMAIL -P "$pw" $OKTA_CMD -r -p $PROFILE
	echo "Saving session to profile: $PROFILE"
}

auth() {
	check_profile
	if [[ "$AUTH" = "BW" ]]
	then
		prep_bw
		unlock_bitwarden_cli
	fi
	authenticate_aws
}



if [[ "$INPUT" == "--help" ]] || [[ "$INPUT" == "-h" ]]
then
	print_help
elif [[ "$INPUT" = "--list-profiles" ]] || [[ "$INPUT" == "-lp" ]]
then
	echo "Profiles:"
	grep -i "\[.*\]" ~/.okta-aws | awk -F'[\[]' '{print $2}' | awk -F'[\]]' '{printf("\t* %s\n", $1)}'
else
	for arg in "$@"
	do
		if [[ "$arg" =~ "profile=" ]]
		then
			TEMP_PROFILE=$(echo $arg | awk -F'=' '{print $2}')
			if [[ -z $TEMP_PROFILE ]]
			then 
				echo "Error. No profile provided. Using default profile: $PROFILE"
			else
				echo "Setting profile to: $TEMP_PROFILE"
				PROFILE=$TEMP_PROFILE
			fi
		
		elif [[ "$arg" == "-f" ]] || [[ "$arg" == "--force-refresh" ]]
		then
			force_refresh="true"
		fi
	done
	prep_okta_file
	auth
fi
