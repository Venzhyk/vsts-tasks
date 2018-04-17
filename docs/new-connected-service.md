
## 1. Go to Account Security Settings and add new AccessToken.


![asd](../imgs/add-access-token-step-1.png) 
![asd](../imgs/add-access-token-step-2.png)

`Release (read, write, execute and manage)` scope shold be enough for `Create Release` task.

![asd](../imgs/add-access-token-step-3.png)


## 2. Then create new Generic Service Endpoint. 

![asd](../imgs/add-service-step-1.png)

![asd](../imgs/add-service-step-2.png)

1. Choose name
2. URL should contain project name

    `http://<vsts-account>.vsrm.visualstudio.com/<project-name>/`
    
    * Do not forget trailing slash '/'!
3. Leave User Name empty
4. Put your new Access Token

![asd](../imgs/add-service-step-3.png)

