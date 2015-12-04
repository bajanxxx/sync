package com.cloudwick.sync.slackbot

import slack.api.SlackApiClient
import scala.concurrent.ExecutionContext.Implicits.global
import scala.util.{Failure, Success}
import slack.rtm.SlackRtmClient
import akka.actor.ActorSystem

/**
  * Created by ashrith on 11/5/15.
  */
object Test {

  val token = "xoxb-13810016625-jExwE2bZe6HGRUAEZPsdRaSt"

  implicit val system = ActorSystem("slack")

  def main(args: Array[String]) {
    /*
      Simple API non-blocking
     */
    val client = SlackApiClient(token)

    val channelsRes = client.listChannels()

    channelsRes.onComplete {
      case Success(channels) => println(channels)
      case Failure(err) => println(err)
    }

    /*
      RTM client
     */
    val clientRTM = SlackRtmClient(token)
    val state = clientRTM.state
    val selfId = state.self.id

    val chanId = state.getChannelIdForName("syncbottesting").get
    println("RTM State: " + state)
    println("RTM ID: " + selfId)
    println("Channel ID: " + chanId)

    clientRTM.onMessage { message =>
      println(s"User: ${message.user}, Message: ${message.text}")
      clientRTM.sendMessage(chanId, message.text)
    }
  }
}
