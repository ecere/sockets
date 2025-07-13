public import IMPORT_STATIC "ecrt"
private:

#define _Noreturn

namespace net;

#ifndef ECERE_NONET

#if defined(__WIN32__)

#define WIN32_LEAN_AND_MEAN
#define String _String
#define SOCKLEN_TYPE int

#include <winsock2.h>
#undef String
static WSADATA wsaData;

#elif defined(__unix__) || defined(__APPLE__)
default:
#define set _set
#define uint _uint
#define SOCKLEN_TYPE socklen_t
#include <sys/time.h>
#include <unistd.h>

#include <netinet/in.h>
#include <netdb.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <sys/time.h>
#include <arpa/inet.h>

#include <poll.h>

#undef set
#undef uint
typedef int SOCKET;
typedef struct hostent HOSTENT;
typedef struct sockaddr SOCKADDR;
typedef struct sockaddr_in SOCKADDR_IN;
typedef struct in_addr IN_ADDR;
#define closesocket(s) close(s)
private:
#endif

// TODO: import "GuiApplication"
import "Service"
import "Socket"

private class SocketSet : byte { bool read:1, write:1, except:1; };

private struct NetworkData
{
   // Connections to the outside world
   OldList sockets;
   // Local services
   OldList services;
   // Ongoing Connections
   OldList connectSockets;
   // Socket Sets

   int ns;

   // Synchronization Elements
   Thread networkThread;
   Semaphore socketsSemaphore;
   Semaphore selectSemaphore;
   bool networkEvent;
   bool connectEvent;
   bool networkInitialized;
   bool networkTerminated;
   uint errorLevel, lastErrorCode;
   bool leftOverBytes;
   Mutex processMutex;
   Mutex mutex;
   int64 mainThreadID;
   OldList mtSemaphores;

private:
#if defined(__WIN32__)
   fd_set readSet, writeSet, exceptSet;

   void setSocket(SocketSet socketSet, SOCKET s)
   {
      if(socketSet.read)   FD_SET(s, &readSet);
      if(socketSet.write)  FD_SET(s, &writeSet);
      if(socketSet.except) FD_SET(s, &exceptSet);
   }

   void clrSocket(SocketSet socketSet, SOCKET s)
   {
      if(socketSet.read)   FD_CLR(s, &readSet);
      if(socketSet.write)  FD_CLR(s, &writeSet);
      if(socketSet.except) FD_CLR(s, &exceptSet);
   }

   void zero(SocketSet socketSet)
   {
      if(socketSet.read)   FD_ZERO(&readSet);
      if(socketSet.write)  FD_ZERO(&writeSet);
      if(socketSet.except) FD_ZERO(&exceptSet);
   }

   void getSocketSets(fd_set * rs, fd_set * ws, fd_set * es)
   {
      *rs = readSet;
      *ws = writeSet;
      *es = exceptSet;
   }
#else
   struct pollfd *pollFDs;
   int numPollFDs, allocedFDs;

   void setSocket(SocketSet socketSet, SOCKET s)
   {
      int i;
      for(i = 0; i < numPollFDs; i++)
         if(pollFDs[i].fd == s)
            break;
      if(i == numPollFDs)
      {
         if(numPollFDs >= allocedFDs)
         {
            allocedFDs = Max(8, allocedFDs + (allocedFDs >> 1));
            pollFDs = renew0 pollFDs struct pollfd[allocedFDs];
         }
         numPollFDs++;
         pollFDs[i].fd = s;
         pollFDs[i].events = 0;
      }

      if(socketSet.read)  pollFDs[i].events |= POLLIN;
      if(socketSet.write) pollFDs[i].events |= POLLOUT;
   }

   void clrSocket(SocketSet socketSet, SOCKET s)
   {
      int i;
      for(i = 0; i < numPollFDs; i++)
         if(pollFDs[i].fd == s)
            break;
      if(i < numPollFDs)
      {
         if(socketSet.read)   pollFDs[i].events &= ~POLLIN;
         if(socketSet.write)  pollFDs[i].events &= ~POLLOUT;
         if(!pollFDs[i].events)
         {
            if(i < numPollFDs-1)
               memmove(&pollFDs[i], &pollFDs[i+1], sizeof(struct pollfd) * (numPollFDs - 1 - i));
            numPollFDs--;
         }
      }
   }

   void zero(SocketSet socketSet)
   {
      if(socketSet.read && socketSet.write)
         numPollFDs = 0;
      else
      {
         int i;

         for(i = 0; i < numPollFDs; i++)
         {
            if(socketSet.read)  pollFDs[i].events &= ~POLLIN;
            if(socketSet.write) pollFDs[i].events &= ~POLLOUT;
         }

         for(i = 0; i < numPollFDs; i++)
         {
            if(!pollFDs[i].events)
            {
               int start = i++;
               int count = 1;

               while(i < numPollFDs && !pollFDs[i].events) i++;

               count = i - start;

               if(i < numPollFDs)
                  memmove(&pollFDs[start], &pollFDs[i], sizeof(struct pollfd) * (numPollFDs - i));
               numPollFDs -= count;
               i = start - 1;
            }
         }
      }
   }

   struct pollfd * getPollFDs(int * count)
   {
      *count = numPollFDs;
      return pollFDs;
   }

   void free()
   {
      delete pollFDs;
      numPollFDs = 0;
      allocedFDs = 0;
   }
#endif
};

#include <errno.h>

NetworkData network;

static class NetworkThread : Thread
{
   uint Main()
   {
#if !defined(__WIN32__)
      struct pollfd * pollFDs = null;
      int nAllocatedFDs = 0;
#endif

      network.mutex.Wait();
      while(!network.networkTerminated)
      {
         int ns = network.ns;

         if(ns)
         {
            int pollResult;
#if defined(__WIN32__)
            struct timeval tv = { 0, 0 }; // TESTING 0 INSTEAD OF (int)(1000000 / 18.2) };

            fd_set selectRS = network.readSet, selectWS = network.writeSet, selectES = network.exceptSet;
#else
            int nPollFDs = network.numPollFDs;
            if(nPollFDs > nAllocatedFDs)
            {
               nAllocatedFDs = nPollFDs;
               pollFDs = renew pollFDs struct pollfd[nAllocatedFDs];
            }
            memcpy(pollFDs, network.pollFDs, sizeof(struct pollfd) * nPollFDs);
#endif

            network.mutex.Release();
   #ifdef DEBUG_SOCKETS
            Log("[N] Waiting for network event...\n");
   #endif

#if defined(__WIN32__)
            pollResult = select(ns, &selectRS, &selectWS, &selectES, &tv);
#else
            pollResult = poll(pollFDs, nPollFDs, 0);
#endif

            if(pollResult)
            {
               network.mutex.Wait();
               network.networkEvent = true;
   #ifdef DEBUG_SOCKETS
               Log("[N] Signaling Network event\n");
   #endif
               // TODO: guiApp.SignalEvent();
   #ifdef DEBUG_SOCKETS
               Log("[N] Waiting for select semaphore in Network Thread...\n");
   #endif
               network.mutex.Release();
               network.selectSemaphore.Wait();
               network.mutex.Wait();
            }
            else
            {
               eC::time::Sleep(1 / 18.2f);
               network.mutex.Wait();
            }
         }
         else
         {
            network.mutex.Release();
            network.socketsSemaphore.Wait();
            network.mutex.Wait();
         }

      }
      network.mutex.Release();
#if !defined(__WIN32__)
      delete pollFDs;
#endif
      return 0;
   }
}

void Network_DetermineMaxSocket()
{
   Service service;
   Socket socket;

   network.mutex.Wait();
   network.ns = 0;
   for(socket = network.sockets.first; socket; socket = socket.next)
      if(!socket.processAlone && !socket.destroyed && socket.s >= network.ns)
         network.ns = (int)(socket.s + 1);
   for(socket = network.connectSockets.first; socket; socket = socket.next)
      if(!socket.destroyed && socket.s >= network.ns)
         network.ns = (int)(socket.s + 1);

   for(service = network.services.first; service; service = service.next)
   {
      if(!service.destroyed && !service.processAlone)
      {
         if(service.s >= network.ns)
            network.ns = (int)(service.s + 1);
      }
      for(socket = service.sockets.first; socket; socket = socket.next)
         if(!socket.destroyed && !socket.processAlone && socket.s >= network.ns)
            network.ns = (int)(socket.s + 1);
   }
   network.mutex.Release();
}

// --- Network System ---
#endif

bool Network_Initialize()
{
#ifndef ECERE_NONET
   if(!network.networkInitialized)
   {
#if defined(__WIN32__) || defined(__unix__) || defined(__APPLE__)
      network.networkInitialized = true;
      network.networkTerminated = false;
#if defined(__WIN32__)
      WSAStartup(0x0002, &wsaData);
#else
      signal(SIGPIPE, SIG_IGN);
#endif

      network.services.Clear();

      network.services.offset = (uint)(uintptr)&((Service)0).prev;
      network.sockets.Clear();

      network.sockets.offset = (uint)(uintptr)&((Socket)0).prev;

      network.connectSockets.Clear();
      network.connectSockets.offset = (uint)(uintptr)&((Socket)0).prev;

#if defined(__WIN32__)
      FD_ZERO(&network.readSet);
      FD_ZERO(&network.writeSet);
      FD_ZERO(&network.exceptSet);
#else
      network.numPollFDs = 0;
#endif

      network.socketsSemaphore = Semaphore { };
      network.selectSemaphore = Semaphore { };
      network.networkThread = NetworkThread { };
      incref network.networkThread;

      network.errorLevel = 2;

      network.processMutex = Mutex { };
      network.mutex = Mutex { };

      network.mainThreadID = GetCurrentThreadID();

      network.networkThread.Create();
#endif
   }
   return true;
#else
   return false;
#endif
}

void Network_Terminate()
{
#ifndef ECERE_NONET

   if(network.networkInitialized)
   {
#if defined(__WIN32__) || defined(__unix__) || defined(__APPLE__)
      Service service;
      Socket socket;

      // TODO: guiApp.PauseNetworkEvents();
      network.networkTerminated = true;

      delete network.processMutex;
      delete network.mutex;

      for(socket = network.connectSockets.first; socket; socket = socket.next)
      {
         socket.connectThread.Wait();
         delete socket.connectThread;
      }

      network.socketsSemaphore.Release();
      network.selectSemaphore.Release();

      network.networkThread.Wait();
      delete network.networkThread;

      // Cleanup External network.sockets
      while((socket = network.sockets.first))
      {
         incref socket;
         //network.sockets.Remove(socket); //THIS IS ALREADY DONE IN Socket::Free
         socket.Free(true);
         if(socket._refCount > 1) socket._refCount--;
         delete socket;
      }
      while((socket = network.connectSockets.first))
      {
         //network.connectSockets.Remove(socket); //THIS IS ALREADY DONE IN Socket::Free
         socket.Free(true);
         delete socket;
      }

      // Cleanup network.services
      while((service = network.services.first))
         service.Stop();

      network.ns = 0;

#if defined(__WIN32__)
      WSACleanup();
#endif

      delete network.selectSemaphore;
      delete network.socketsSemaphore;
#endif
#ifdef DEBUG_SOCKETS
      Log("[P] Network System Terminated\n");
#endif
      network.networkInitialized = false;
   }

#if !defined(__WIN32__)
   network.free();
#endif

#endif
}

#ifndef ECERE_NONET

public bool GetAddressFromName(const char * hostName, char * inetAddress)
{
   HOSTENT * host;

   if(!Network_Initialize())
      return false;

   host = gethostbyname(hostName);
   if(host)
   {
      strcpy(inetAddress, inet_ntoa(*((IN_ADDR *)host->h_addr)));
      return true;
   }
   return false;
}

public bool GetNameFromAddress(const char * inetAddress, char * hostName)
{
   struct in_addr in;
   HOSTENT * host;

   if(!Network_Initialize())
      return false;

   in.s_addr = inet_addr(inetAddress);
   host = gethostbyaddr((char *)&in, 4, PF_INET);
   if(host)
   {
      strcpy(hostName, host->h_name);
      return true;
   }
   return false;
}

public bool GetHostName(char * hostName, int size)
{
   if(!Network_Initialize())
      return false;

   return !gethostname(hostName,size);
}

#if !defined(ECERE_VANILLA) && !defined(ECERE_NONET)

public bool ProcessNetworkEvents()
{
   bool gotEvent = false;

#if defined(__WIN32__) || defined(__unix__) || defined(__APPLE__)
   if(network.networkInitialized)
   {
      Service service;
      Socket socket, next;
#if defined(__WIN32__)
      fd_set rs, ws, es;
#else
      int nPollFDs = 0;
      struct pollfd * pollFDs = null;
#endif
      Service nextService;
      OldLink semPtr;
      int pollingResult = 0;

      PauseNetworkEvents();
      network.mutex.Wait();

#ifdef DEBUG_SOCKETS
      if(network.connectEvent || network.networkEvent)
         Log("[P] [NProcess]\n");
#endif

#if defined(__WIN32__)
      if(network.ns)
      {
         struct timeval tv = {0, 0};
         network.getSocketSets(&rs, &ws, &es);
         pollingResult = select(network.ns, &rs, &ws, &es, &tv);
      }
#else
      if(network.ns)
      {
         pollFDs = network.getPollFDs(&nPollFDs);
         pollingResult = poll(pollFDs, nPollFDs, 0) > 0;
      }
#endif

      if(pollingResult || network.leftOverBytes)
      {
         network.leftOverBytes = false;

         // Danger here? Why looping with a next and not unlocking anything?
         for(socket = network.connectSockets.first; socket; socket = next)
         {
            next = socket.next;
            if(!socket.processAlone)
            {
               SOCKET s = socket.s;
               bool readyToWrite;
#if defined(__WIN32__)
               readyToWrite = FD_ISSET(s, &ws) != 0;
#else
               int i;
               readyToWrite = false;
               for(i = 0; i < nPollFDs; i++)
               {
                  if(pollFDs[i].fd == s)
                  {
                     readyToWrite = (pollFDs[i].revents & POLLOUT) != 0;
                     break;
                  }
               }
#endif
               if(readyToWrite)
               {
                  network.mutex.Release();
                  socket.connectThread.Wait();
                  network.mutex.Wait();
               }
            }
         }
         for(socket = network.sockets.first; socket; socket = next)
         {
            next = socket.next;
            if(!socket.processAlone)
            {
               bool readyToRead, errorCondition;
               SOCKET s = socket.s;
#if defined(__WIN32__)
               readyToRead = FD_ISSET(s, &rs) != 0;
               errorCondition = FD_ISSET(s, &es) != 0;
#else
               int i;
               readyToRead = false;
               errorCondition = false;
               for(i = 0; i < nPollFDs; i++)
               {
                  if(pollFDs[i].fd == s)
                  {
                     readyToRead = (pollFDs[i].revents & POLLIN) != 0;
                     errorCondition = (pollFDs[i].revents & (POLLERR | POLLHUP)) != 0;
                     break;
                  }
               }
#endif
               network.mutex.Release();
               gotEvent |= socket.ProcessSocket(readyToRead, errorCondition);
               network.mutex.Wait();
            }
         }

         for(service = network.services.first; service; service = nextService)
         {
            nextService = service.next;
            if(!service.processAlone)
            {
               bool readyToRead;
               SOCKET s = service.s;

#if defined(__WIN32__)
               readyToRead = FD_ISSET(s, &rs) != 0;
#else
               int i;
               readyToRead = false;
               for(i = 0; i < nPollFDs; i++)
               {
                  if(pollFDs[i].fd == s)
                  {
                     readyToRead = (pollFDs[i].revents & POLLIN) != 0;
                     break;
                  }
               }
#endif

               if(readyToRead)
               {
   #ifdef DEBUG_SOCKETS
                  Logf("[P] Accepting connection (%x)\n", service.s);
   #endif
                  service.accepted = false;
                  service.OnAccept();
                  if(!service.accepted)
                  {
                     SOCKET s;
                     SOCKADDR_IN a;
                     SOCKLEN_TYPE addrLen = sizeof(a);
                     s = accept(service.s,(SOCKADDR *)&a,&addrLen);
                     closesocket(s);
                  }
                  gotEvent |= true;

   #ifdef DEBUG_SOCKETS
                  Log("[P] Connection accepted\n");
   #endif
               }
            }
            for(socket = service.sockets.first; socket; socket = next)
            {
               next = socket.next;
               if(!socket.processAlone)
               {
                  SOCKET s = socket.s;
                  bool readyToRead, errorCondition;
#if defined(__WIN32__)
                  readyToRead = FD_ISSET(s, &rs) != 0;
                  errorCondition = FD_ISSET(s, &es) != 0;
#else
                  int i;
                  readyToRead = false;
                  errorCondition = false;
                  for(i = 0; i < nPollFDs; i++)
                  {
                     if(pollFDs[i].fd == s)
                     {
                        readyToRead = (pollFDs[i].revents & POLLIN) != 0;
                        errorCondition = (pollFDs[i].revents & (POLLERR | POLLHUP)) != 0;
                        break;
                     }
                  }
#endif
                  network.mutex.Release();
                  gotEvent |= socket.ProcessSocket(readyToRead, errorCondition);
                  network.mutex.Wait();
               }
            }
         }
      }
      if(network.connectEvent)
      {
         bool goOn = true;
         while(goOn)
         {
            goOn = false;
            for(socket = network.connectSockets.first; socket; socket = next)
            {
               next = socket.next;
               if(socket._connected && socket._connected != -2)
               {
                  network.connectSockets.Remove(socket);
                  delete socket.connectThread;

                  // printf("%s is connected = %d\n", socket._class.name, socket._connected);
                  if(socket._connected == -1)
                  {
   #ifdef DEBUG_SOCKETS
                     Logf("[P] Processing disconnected connect (%x)\n", socket.s);
   #endif
   #if 0
                     if(socket.disconnectCode == ResolveFailed)
                        Logf("Error resolving address %s\n", socket.address);
   #endif
                     if(socket.s == network.ns - 1)
                        Network_DetermineMaxSocket();

                     socket._connected = 0;
                     socket.Free(false);
                     delete socket;
                  }
                  else if(socket._connected == 1)
                  {
   #ifdef DEBUG_SOCKETS
                     Log("[P] Processing connected connect\n");
   #endif
                     network.clrSocket({ write = true }, socket.s);
                     network.setSocket({ read = true, except = true }, socket.s);
                     network.mutex.Release();

                     // printf("Calling OnConnect on %s\n", socket._class.name);
                     socket.OnConnect();
                     network.mutex.Wait();
                     if(socket._connected)
                        network.sockets.Add(socket);
                  }
                  gotEvent |= true;
                  goOn = true;
                  break;
               }
            }
         }
         network.connectEvent = false;
      }
      if(network.networkEvent)
      {
         network.networkEvent = false;
         network.selectSemaphore.Release();
      }

      if(gotEvent)
      {
         for(semPtr = network.mtSemaphores.first; semPtr; semPtr = semPtr.next)
         {
            ((Semaphore)semPtr.data).Release();
         }
      }

      network.mutex.Release();
      ResumeNetworkEvents();
   }
#endif
   return gotEvent;
}

public void WaitNetworkEvent()
{
   if(network.networkInitialized)
   {
      if(GetCurrentThreadID() == network.mainThreadID)
      {
         WaitEvent();
      }
      else
      {
         Semaphore semaphore { };
         OldLink semPtr { data = semaphore };
         network.mutex.Wait();
         network.mtSemaphores.Add(semPtr);
         network.mutex.Release();

         ResumeNetworkEvents();
         semaphore.Wait();
         PauseNetworkEvents();
         network.mutex.Wait();
         network.mtSemaphores.Delete(semPtr);
         network.mutex.Release();
         delete semaphore;
      }
   }
}

public void PauseNetworkEvents()
{
   if(network.networkInitialized)
   {
      network.processMutex.Wait();
   }
}

public void ResumeNetworkEvents()
{
   if(network.networkInitialized)
   {
      network.processMutex.Release();
   }
}
#endif

#endif
