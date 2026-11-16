<?xml version="1.0"?>
<!-- SPDX-License-Identifier: CC0-1.0 -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!-- Forester 6 emits HTML directly. Apply the theme's XSLT to each bibliography block. -->
  <xsl:import href="core.xsl" />
  <xsl:import href="metadata.xsl" />
  <xsl:output method="html" encoding="utf-8" indent="no" omit-xml-declaration="yes" />

  <xsl:template match="/">
    <xsl:apply-templates />
  </xsl:template>

  <xsl:template match="@* | node()">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="pre[not(*)][starts-with(normalize-space(.), '@')]">
    <xsl:variable name="text">
      <xsl:call-template name="preformatted-content" />
    </xsl:variable>
    <xsl:copy>
      <xsl:apply-templates select="@*[name() != 'class']" />
      <xsl:attribute name="class">
        <xsl:value-of select="normalize-space(concat(@class, ' bibtex'))" />
      </xsl:attribute>
      <xsl:comment>This is a guard for intentional leading blank lines.</xsl:comment>
      <xsl:call-template name="highlight-bibtex">
        <xsl:with-param name="text" select="string($text)" />
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
