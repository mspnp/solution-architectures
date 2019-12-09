"use strict";

var connection = new signalR.HubConnectionBuilder().withUrl("http://localhost:7071/api/").build();

//Hide connection status until connection is established
document.getElementById("status").style.display = 'none';
var channel = "notify"; //name of the channel to which the message was sent in the Hub

connection.on(channel, function (message) {

    var msg = message.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    var encodedMsg =  msg;
    var li = document.createElement("li");
    li.textContent = encodedMsg;
    document.getElementById("messagesList").appendChild(li);
});

connection.start().then(function () {
    document.getElementById("status").style.display = 'inline-block';
}).catch(function (err) {
    return console.error(err.toString());
});