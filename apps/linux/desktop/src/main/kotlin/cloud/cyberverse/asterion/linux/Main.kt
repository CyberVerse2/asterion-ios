package cloud.cyberverse.asterion.linux

import cloud.cyberverse.asterion.core.net.Hosts
import cloud.cyberverse.asterion.core.reader.ReaderParagraphs

/**
 * Linux desktop entry point (phase 1: JVM shell).
 *
 * Proves the shared Android `core/` runs on a Linux desktop JVM with the same
 * paragraph rule and service origins as every other client. Phase 2 replaces
 * this printout with the Compose Multiplatform window; the packaging script
 * already ships whatever this module installs.
 */
fun main(args: Array<String>) {
    val version = System.getProperty("asterion.version", "dev")
    println("Asterion for Linux $version (java ${System.getProperty("java.version")})")

    val sample = ReaderParagraphs.split(
        "Chapter 1: Awakening",
        "<p>Chapter 1: Awakening</p><p>The hall was dark.</p><br>Translator: Someone",
    )
    println("paragraphs=${sample.size} sample=${sample.firstOrNull().orEmpty()}")
    println("api=${Hosts.CORE} anime=${Hosts.ANIME} movies=${Hosts.MOVIES} football=${Hosts.FOOTBALL} manga=${Hosts.MANGA}")

    val contracts = System.getProperty("asterion.contracts", "<contracts not set>")
    println("contracts=$contracts")

    if (args.contains("--verify")) {
        check(sample == listOf("The hall was dark.")) {
            "paragraph parity failed: $sample"
        }
        println("verify: OK")
    }
}
