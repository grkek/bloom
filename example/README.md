## Usage

Run the example using:

```
crystal run example/borjomi.cr --error-trace
```

You can execute an example procedure by calling the location and providing the data:

```
curl --location 'localhost:8118/twirp/borjomi.Services.Gate/OpenLock' \
     --header 'Content-Type: application/json' \
     --data '{ "id": "1" }'
```
