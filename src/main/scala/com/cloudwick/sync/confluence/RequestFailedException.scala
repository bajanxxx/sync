package com.cloudwick.sync.confluence

case class RequestFailedException(message: String) extends Exception(message)