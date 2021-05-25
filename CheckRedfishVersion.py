import requests, json, sys, re, time, warnings, argparse

from datetime import datetime

warnings.filterwarnings("ignore")

parser=argparse.ArgumentParser(description="Python script using Redfish API to either get current iBMC user settings, create iBMC user or delete iBMC user using the user account ID")
parser.add_argument('-ip',help='iBMC IP address', required=True)
parser.add_argument('-u', help='iBMC username', required=True)
parser.add_argument('-p', help='iBMC password', required=True)

args=vars(parser.parse_args())

iBMC_ip=args["ip"]
iBMC_username=args["u"]
iBMC_password=args["p"]
# if args["C"]:
#     try:
#         new_iBMC_username = args["U"]
#         new_iBMC_password = args["P"]
#         new_iBMC_user_enable = args["E"].title()
#         new_iBMC_user_role = args["R"]
#     except:
#         print("\n- FAIL, missing one or multiple required arguments to create new iBMC user. You must use -C, -U, -P, -E and -R arguments to create a new iBMC user")
#         sys.exit()
#     if new_iBMC_user_enable == "True":
#         new_iBMC_user_enable = True
#     elif new_iBMC_user_enable == "False":
#         new_iBMC_user_enable = False
            

def check_Redfish_version():
    response = requests.get('https://%s/redfish' % iBMC_ip,verify=False,auth=(iBMC_username, iBMC_password))
    data = response.json()
    if response.status_code != 200:
        print("\n- WARNING, Redfish version could not get")
        sys.exit()
    else:
        pass

    
    


if __name__ == "__main__":
    check_Redfish_version()
