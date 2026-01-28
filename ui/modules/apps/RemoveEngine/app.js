(function() {
  'use strict';

  angular.module('beamng.apps')
    .directive('removeEngine', ['$injector', '$timeout', '$q', '$interval', function($injector, $timeout, $q, $interval) {
      return {
        templateUrl: '/ui/modules/apps/RemoveEngine/app.html',
        replace: true,
        restrict: 'EA',
        scope: true,
        link: function(scope, element) {
          var FLASH_DURATION = 5000;
          var STYLE_ID = 'remove-engine-app-stylesheet';
          var luaCommandCache = Object.create(null);
          var flashTimer = null;
          var lastVehicleHash = null;
          var beamApi = window.bngApi;
          var StreamsManager = safeGet('StreamsManager');
          var streamsList = ['vehicles'];
          var pollHandle = null;
          var scheduleRefresh = createDebouncer(function(options) {
            scope.refreshState(options);
          }, 150);

          scope.state = {
            vehicleId: null,
            vehicleName: 'No vehicle detected',
            slotLabel: null,
            statusText: 'Spawn a vehicle to continue',
            buttonLabel: 'Set Engine To Empty',
            buttonColor: 'rgba(90, 98, 107, 0.45)',
            canRemove: false,
            isEmpty: true,
            busy: false,
            error: null,
            message: null
          };

          element.ready(ensureStylesheet);
          if (StreamsManager && StreamsManager.add) {
            StreamsManager.add(streamsList);
          } else {
            startPolling();
          }

          function safeGet(token) {
            try {
              return $injector.get(token);
            } catch (err) {
              console.warn('RemoveEngine: unable to resolve dependency "' + token + '"', err);
              return null;
            }
          }

          function ensureStylesheet() {
            if (document.getElementById(STYLE_ID)) {
              return;
            }
            var linkEl = document.createElement('link');
            linkEl.id = STYLE_ID;
            linkEl.rel = 'stylesheet';
            linkEl.type = 'text/css';
            linkEl.href = '/ui/modules/apps/RemoveEngine/app.css';
            document.head.appendChild(linkEl);
          }

          function clearFlashTimer() {
            if (flashTimer) {
              $timeout.cancel(flashTimer);
              flashTimer = null;
            }
          }

          function startFlashTimer() {
            clearFlashTimer();
            flashTimer = $timeout(function() {
              scope.state.error = null;
              scope.state.message = null;
              flashTimer = null;
            }, FLASH_DURATION);
          }

          function setError(message) {
            scope.state.error = message;
            scope.state.message = null;
            startFlashTimer();
          }

          function setMessage(message) {
            scope.state.message = message;
            scope.state.error = null;
            startFlashTimer();
          }

          function getLuaCommand(methodName) {
            if (!luaCommandCache[methodName]) {
              luaCommandCache[methodName] = [
                '(function()',
                'local extName = "core_RemoveEngine"',
                'if not extensions.isExtensionLoaded(extName) then',
                '  extensions.load(extName)',
                'end',
                'if extensions.core_RemoveEngine and extensions.core_RemoveEngine.' + methodName + ' then',
                '  return extensions.core_RemoveEngine.' + methodName + '()',
                'end',
                'return jsonEncode({success = false, message = "RemoveEngine extension unavailable."})',
                'end)()'
              ].join('\n');
            }
            return luaCommandCache[methodName];
          }

          function invokeExtension(methodName) {
            if (!beamApi || typeof beamApi.engineLua !== 'function') {
              return $q.reject('BeamNG API unavailable');
            }

            var deferred = $q.defer();
            var settled = false;

            function settle(handler, payload) {
              if (settled) {
                return;
              }
              settled = true;
              handler(payload);
            }

            try {
              var maybePromise = beamApi.engineLua(getLuaCommand(methodName), function(result) {
                settle(deferred.resolve, result);
              });

              if (maybePromise && typeof maybePromise.then === 'function') {
                maybePromise.then(function(result) {
                  settle(deferred.resolve, result);
                }, function(err) {
                  settle(deferred.reject, err);
                });
              } else if (typeof maybePromise !== 'undefined') {
                settle(deferred.resolve, maybePromise);
              }
            } catch (err) {
              settle(deferred.reject, err || 'BeamNG engineLua invocation failed');
            }

            return deferred.promise;
          }

          function applyButtonState() {
            if (scope.state.busy) {
              scope.state.buttonLabel = 'Working...';
              scope.state.buttonColor = 'rgba(90, 118, 147, 0.75)';
              return;
            }
            if (!scope.state.canRemove) {
              scope.state.buttonColor = 'rgba(90, 98, 107, 0.45)';
              scope.state.buttonLabel = scope.state.isEmpty ? 'Engine Already Empty' : 'Unavailable';
            } else {
              scope.state.buttonColor = 'rgba(126, 214, 140, 0.55)';
              scope.state.buttonLabel = 'Set Engine To Empty';
            }
          }

          function parseResult(raw) {
            if (!raw || raw === 'null') {
              return {};
            }
            if (angular.isObject(raw)) {
              return raw;
            }
            if (typeof raw === 'string') {
              try {
                return JSON.parse(raw);
              } catch (e) {
                console.error('RemoveEngine: unable to parse payload', e, raw);
              }
            }
            return {};
          }

          function updateStateFromPayload(data, options) {
            options = options || {};
            var preserveFeedback = !!options.preserveFeedback;
            var allowStatusMessage = !!options.allowStatusMessage;

            if (!data.success) {
              scope.state.vehicleId = null;
              scope.state.vehicleName = 'No vehicle detected';
              scope.state.slotLabel = null;
              scope.state.statusText = data.message || 'Spawn a vehicle to continue';
              scope.state.canRemove = false;
              scope.state.isEmpty = false;
              if (data.message) {
                setError(data.message);
              } else if (!preserveFeedback) {
                scope.state.message = null;
                scope.state.error = null;
                clearFlashTimer();
              }
              return;
            }

            var slotId = data.slotId || null;
            var slotLabel = data.slotLabel || slotId;
            var partName = data.partName || '';
            scope.state.vehicleId = data.vehicleId;
            scope.state.vehicleName = data.vehicleName || 'Active vehicle';
            scope.state.slotLabel = slotLabel;
            scope.state.isEmpty = !!data.isEmpty;

            if (!slotId) {
              scope.state.statusText = 'No engine slot detected';
              scope.state.canRemove = false;
            } else if (scope.state.isEmpty) {
              scope.state.statusText = 'Engine already empty';
              scope.state.canRemove = false;
            } else {
              scope.state.statusText = partName ? ('Installed: ' + partName) : 'Engine installed';
              scope.state.canRemove = true;
            }

            scope.state.error = null;
            if (data.message && allowStatusMessage) {
              setMessage(data.message);
            } else if (!preserveFeedback && !allowStatusMessage) {
              scope.state.message = null;
              clearFlashTimer();
            }
          }

          scope.refreshState = function(options) {
            options = options || {};
            return invokeExtension('getEngineSlotInfo')
              .then(function(result) {
                var data = parseResult(result);
                updateStateFromPayload(data, options);
                applyButtonState();
              }, function() {
                setError('Unable to communicate with BeamNG Lua runtime.');
                scope.state.canRemove = false;
                scope.state.vehicleName = 'No vehicle detected';
                applyButtonState();
              });
          };

          scope.setEngineEmpty = function() {
            if (scope.state.busy || !scope.state.canRemove) {
              return;
            }
            scope.state.busy = true;
            applyButtonState();
            invokeExtension('setEngineEmpty')
              .then(function(result) {
                scope.state.busy = false;
                var data = parseResult(result);
                if (data.success) {
                  setMessage(data.message || 'Engine removed.');
                  scope.state.isEmpty = true;
                  scope.state.canRemove = false;
                  applyButtonState();
                  scope.refreshState({ preserveFeedback: true });
                } else {
                  setError(data.message || 'Failed to remove engine.');
                  applyButtonState();
                }
              }, function() {
                scope.state.busy = false;
                setError('Failed to execute engine removal command.');
                applyButtonState();
              });
          };

          function deriveVehicleId(vehiclesStream) {
            if (!vehiclesStream) {
              return null;
            }
            var numericFields = ['focusVehicleId', 'vehicleId', 'vid', 'playerVehicleId', 'id'];
            for (var i = 0; i < numericFields.length; i++) {
              var field = numericFields[i];
              if (angular.isNumber(vehiclesStream[field])) {
                return vehiclesStream[field];
              }
            }
            var focusVehicle = vehiclesStream.focusVehicle;
            if (focusVehicle) {
              return focusVehicle.vid || focusVehicle.vehicleId || focusVehicle.id || null;
            }
            if (angular.isArray(vehiclesStream) && vehiclesStream.length > 0) {
              var first = vehiclesStream[0];
              return first.vid || first.vehicleId || first.id || null;
            }
            return null;
          }

          scope.$on('streamsUpdate', function(event, streams) {
            if (!StreamsManager) {
              return;
            }
            var vehiclesStream = streams && streams.vehicles;
            var snapshot = vehiclesStream && JSON.stringify(vehiclesStream);
            if (!snapshot) {
              return;
            }
            if (snapshot !== lastVehicleHash) {
              lastVehicleHash = snapshot;
              scheduleRefresh();
            }
          });

          scope.$on('app:vehicleChanged', scheduleRefresh);
          scope.$on('app:resetVehicle', scheduleRefresh);
          scope.$on('VehicleFocusChanged', scheduleRefresh);
          scope.$on('VehicleReset', scheduleRefresh);
          scope.$on('VehicleChange', scheduleRefresh);

          function startPolling() {
            if (pollHandle) {
              return;
            }
            pollHandle = $interval(function() {
              scope.refreshState();
            }, 2000);
          }

          function stopPolling() {
            if (pollHandle) {
              $interval.cancel(pollHandle);
              pollHandle = null;
            }
          }

          function createDebouncer(callback, delay) {
            var pendingTimer = null;
            return function() {
              var args = arguments;
              if (pendingTimer) {
                $timeout.cancel(pendingTimer);
              }
              pendingTimer = $timeout(function() {
                pendingTimer = null;
                callback.apply(null, args);
              }, delay);
            };
          }

          scope.$on('$destroy', function() {
            if (StreamsManager && StreamsManager.remove) {
              StreamsManager.remove(streamsList);
            }
            clearFlashTimer();
            stopPolling();
          });

          scope.refreshState();
        }
      };
    }]);
})();
