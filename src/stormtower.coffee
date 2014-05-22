
# The stormtower class which starts jappajs service and
# acts as a proxy between stormgate/stormlight to communicate with VSC stormflash

StormAgent = require 'stormagent'

StormData = StormAgent.StormData

class TowerAgent extends StormData

    async = require 'async'
    http = require 'http'
    crypto = require 'crypto'

    constructor: (@id, @bolt) ->
        @status = false
        @checksum = null
        @monitoring = false

        super id

    monitor: (interval) ->
        return if @monitoring # we don't want to schedule this multiple times...

        extend = require('util')._extend

        @monitoring = true
        async.whilst(
            () =>
                @monitoring
            (repeat) =>
                @check
                try
                    streamBuffers = require 'stream-buffers'
                    req = new streamBuffers.ReadableStreamBuffer
                    req.method = 'GET'
                    req.url    = '/'
                    req.target = 5000

                    @log "monitor - checking #{@bolt.id} for status"
                    relay = @bolt.relay req
                catch err
                    @log "monitor - agent discovery request failed:", err
                    setTimeout repeat, interval

                relay.on 'reply', (reply) =>
                    try
                        status = JSON.parse reply.body
                        copy = extend({},status)
                        delete copy.os # os info changes all the time...
                        md5 = crypto.createHash "md5"
                        md5.update JSON.stringify copy
                        checksum = md5.digest "hex"
                        unless checksum is @checksum
                            @checksum = checksum
                            unless @status
                                @emit 'ready'
                            @status = status
                            @emit 'changed'
                    catch err
                        @log "unable to parse reply:", reply
                        @log "error:", err
                        relay.end()

                @log "monitor - scheduling repeat at #{interval}"
                setTimeout repeat, interval
            (err) =>
                @log "monitor - agent discovery stopped for: #{@id}"
                @monitoring = false
        )

    destroy: ->
        @monitoring = false

#-----------------------------------------------------------------

StormRegistry = StormAgent.StormRegistry

class TowerRegistry extends StormRegistry

    constructor: (filename) ->
        @on 'removed', (tagent) ->
            tagent.destroy() if tagent.destroy?

        super filename

    get: (key) ->
        entry = super key
        return unless entry? and entry.status?
        entry.status.id ?= entry.id
        entry.status

#-----------------------------------------------------------------

StormBolt = require 'stormbolt'

class StormTower extends StormBolt

    # Constructor for stormtower class
    constructor: (config) ->
        super config
        # key routine to import itself
        @import module

        @agents = new TowerRegistry

        @clients.on 'added', (bolt) =>
            tagent = new TowerAgent bolt.id, bolt
            tagent.monitor @config.monitorInterval

            # during monitoring, ready will be emitted once status is retrieved
            tagent.once 'ready', =>
                @agents.add bolt.id, tagent
                tagent.on 'changed', =>
                    @agents.emit 'changed'

        @clients.on 'removed', (bolt) =>
            @log "boltstream #{bolt.id} is removed"
            @agents.remove bolt.id

    # super class overrides
    status: ->
        state = super
        state.agents = @agents.list()
        state

#module.exports = stormtower
module.exports = StormTower

