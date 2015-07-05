package com.cloudwick.sync.confluence

import java.io.File
import java.net.URLEncoder

import com.typesafe.config.ConfigFactory
import org.jsoup.Jsoup
import play.api.libs.json._

import scala.util.Try
import scalaj.http.{HttpResponse, HttpOptions, Http}

object Request {

  private lazy val config = ConfigFactory.load()

  private def confluenceSrv(url: String) = {
    Http(url)
      .auth(
        config.getString("confluence.auth.username"),
        config.getString("confluence.auth.password"))
      .option(_.setInstanceFollowRedirects(true))
      .option(HttpOptions.connTimeout(10000))
      .option(HttpOptions.readTimeout(50000))
  }

  private def confluenceGET(url: String): Try[HttpResponse[String]] = {
    Try {
      val response = confluenceSrv(url).asString
      response.code match {
        case 200 => response
        case _ =>
          println(s"Caught 404 on the request: $url, reason: ${response.body}")
          throw new RequestFailedException("Request failed")
      }
    }
  }

  private def confluencePOST(url: String, data: Array[Byte]): Try[HttpResponse[String]] = {
    Try {
      val response = confluenceSrv(url)
        .postData(data)
        .header("content-type", "application/json")
        .asString
      response.code match {
        case 200 => response
        case _ =>
          println(s"Caught 404 on the request: $url, reason: ${response.body}")
          throw new RequestFailedException("Request failed")
      }
    }
  }

  private def getJson[T](url: String) = {
    for {
      res <- confluenceGET(url)
    } yield Json.parse(res.body)
  }

  private def postJson[T](url: String, data: JsValue) = {
    for {
      res <- confluencePOST(url, data.toString().getBytes)
    } yield Json.parse(res.body)
  }

  def createPage(page: Page) = {
    val pageJsonData = constructPageReq(page)
    // debug
    println(pageJsonData)
    postJson(config.getString("confluence.base-url") + "/content", pageJsonData).map { content =>
      Some(content \ "history" \ "createdDate")
    } getOrElse {
      // Failed creating page
      None
    }
  }

  private def constructPageReq(page: Page): JsValue = page.ancestorId.isDefined match {
    // {"type":"page","title":"new page","space":{"key":"~ashrith"},"body":{"storage":{"value":"<p>This is a new page</p>","representation":"storage"}}}
    case true =>
      Json.obj(
        "type" -> "page",
        "title" -> page.pTitle,
        "space" -> Json.obj(
          "key" -> page.sKey
        ),
        "ancestors" -> Json.arr(
          Json.obj(
            "id" -> page.ancestorId.get,
            "type" -> "page"
          )
        ),
        "body" -> Json.obj(
          "storage" -> Json.obj(
            "value" -> page.pBody,
            "representation" -> "storage"
          )
        )
      )
    case _ =>
      Json.obj(
        "type" -> "page",
        "title" -> page.pTitle,
        "space" -> Json.obj(
          "key" -> page.sKey
        ),
        "body" -> Json.obj(
          "storage" -> Json.obj(
            "value" -> page.pBody,
            "representation" -> "storage"
          )
        )
      )
  }

  def listSpaces = {
    getJson(config.getString("confluence.base-url") + "/space").map { content =>
      (content \ "results").validate[List[Space]].get
    } getOrElse {
      // log this message -> println("Something went wrong fetching spaces")
      List()
    }
  }

  def validateSpace(spaceKey: String): Boolean = {
    listSpaces.map(space => space.sKey).contains(spaceKey)
  }

  def getSpace(spaceKey: String) = {
    getJson(config.getString("confluence.base-url") + "/space" + s"/$spaceKey").map { content =>
      Some(content.validate[Space].get)
    } getOrElse {
      None
    }
  }

  def getPageId(spaceKey: String, pageName: String) = {
    val urlSafePageName = URLEncoder.encode(pageName, "UTF-8")
    val url = config.getString("confluence.base-url") + s"/content?spaceKey=$spaceKey&title=$urlSafePageName"
    getJson(url).map { content =>
      Some(((content \ "results")(0) \ "id").validate[String].get)
    } getOrElse {
      None
    }
  }

  def main(args: Array[String]): Unit = {
    /*
    // 1. this will result in success and will yield a Space object
    getSpace("~ashrith").foreach(println)
    // 2. this will result in failure and will print an error message of why it failed
    getSpace("~ashrithmekala").foreach(println)
    // 3. this will create a new page if it does not exist in the specified space otherwise it throws an error
    val p = Page("~ashrith", "test page", "<p>This is a new test page.</p>")
    createPage(p).foreach(println(_))
    // 4. create a new child page
    createPage(
      Page(
        "SPAR",
        "test page",
        "<p>This is a test page create by Sync.</p>",
        getPageId("SPAR", "Release Notes")
      )
    )
    */
    // 5. Get a html file and insert into confluence
    val document = Jsoup.parse(new File("/tmp/spark-release-0.3.html"), "UTF-8", "http://spark.apache.org/releases/")
    val mainDiv = document.select("div.row > div").get(1)
    // val body = mainDiv.html().replaceAll("\"", "\\\\\"").replaceAll("(\\r|\\n|\\r\\n)+", "")
    // double quotes will be escaped by JsString
    // http://stackoverflow.com/questions/1946426/html-5-is-it-br-br-or-br
    val body = mainDiv.html().replaceAll("(<br.*?>)", "<br/>").replaceAll("(\\r|\\n|\\r\\n)+", "")
    val page = Page("SPAR", "Apache Spark Release Notes 0.3", body, getPageId("SPAR", "Release Notes"))
    createPage(page)
  }
}
