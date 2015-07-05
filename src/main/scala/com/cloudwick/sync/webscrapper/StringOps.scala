package com.cloudwick.sync.webscrapper

/**
 * Companion method containing the implicit conversion to RichString
 * @author ashrith
 */
object StringOps {
  val releasePagesStartsWith = Seq("spark-release")

  /**
   * Simple PimpMyLibrary class to see if a string starts with release tagged pages
   * @param string String to wrap
   */
  implicit class RichString(val string: String) extends AnyVal {
    def hasReleasePagePrefix: Boolean = releasePagesStartsWith.find(string startsWith _).isDefined
  }
}
