import boto3
import json

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('visitor_count2')

def lambda_handler(event, context):
   
    response = table.get_item(
        Key={

            'visitor_id': 'visitor'
        }
    )
            
            
    count = response['Item']['count']
    count = str(int(count) + 1)         
            
            
  
    
    response = table.put_item(
        Item = {
            'visitor_id': 'visitor',
            'count': count
        }
    )
   
           
      
    return {
        'statusCode': 200,
        'body':json.dumps({"visitor":str(count)}),
        'headers': {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
        'Access-Control-Allow-Headers':'*'
        }
    }
